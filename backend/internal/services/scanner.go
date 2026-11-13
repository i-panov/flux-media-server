package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"gopkg.in/vansante/go-ffprobe.v2"
	"gorm.io/gorm"

	"flux/internal/config"
	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

// ErrScanInProgress is returned when a scan for the same path is already running.
var ErrScanInProgress = errors.New("scan already in progress")

const quickHashChunk = 1024 * 1024 // 1MB head/tail for quick hash

// Единый источник списков расширений: сканер, thumbnail, metadata-экстрактор
// и fallback-определение типа используют эти таблицы, чтобы не расходиться.
var (
	videoExtensions = map[string]bool{
		".mp4": true, ".m4v": true, ".mkv": true, ".avi": true, ".mov": true,
		".wmv": true, ".webm": true, ".flv": true, ".ts": true,
	}
	audioExtensions = map[string]bool{
		".mp3": true, ".flac": true, ".ogg": true, ".oga": true,
		".m4a": true, ".aac": true, ".wav": true, ".opus": true, ".wma": true,
	}
	imageExtensions = map[string]bool{
		".jpg": true, ".jpeg": true, ".png": true,
		".gif": true, ".webp": true, ".bmp": true,
	}
)

// ApplyVideoDimensions переносит размеры кадра из метаданных файла в
// запись.
//
// В отличие от пользовательских полей (title/artist/album/genre),
// размеры перезаписываются ВСЕГДА: файл по тому же пути мог быть
// заменён на другой (с другим разрешением), и оставленные старые
// пропорции вели бы к неверной ориентации в плеере. Нулевые значения
// (ffprobe не отдал) игнорируются — иначе запись потеряла бы уже
// известные размеры.
func ApplyVideoDimensions(media *models.Media, meta *FileMetadata) {
	if meta == nil {
		return
	}
	if meta.Width > 0 {
		media.Width = meta.Width
	}
	if meta.Height > 0 {
		media.Height = meta.Height
	}
}

func IsAllowedExtension(ext string) bool {
	return videoExtensions[ext] || audioExtensions[ext] || imageExtensions[ext]
}

type ScannerService struct {
	mediaRepo     repository.MediaRepository
	config        *config.Config
	metaExtractor *MetadataExtractor
	thumbService  *ThumbnailService

	mu       sync.RWMutex
	statuses map[string]*ScanStatus

	// scanFile сериализует обработку одного файла: watcher и полный скан
	// могут прийти одновременно и создать две записи на один путь.
	fileMu sync.Mutex
}

func NewScannerService(
	mediaRepo repository.MediaRepository,
	config *config.Config,
) *ScannerService {
	return &ScannerService{
		mediaRepo:     mediaRepo,
		config:        config,
		metaExtractor: NewMetadataExtractor(),
		thumbService:  NewThumbnailService(config.Media.ThumbnailPath),
		statuses:      make(map[string]*ScanStatus),
	}
}

// ScanAll сканирует все сконфигурированные медиа-пути. Ошибки отдельных
// путей не прерывают остальные сканы, но первая ошибка возвращается.
func (s *ScannerService) ScanAll(ctx context.Context) error {
	paths := s.config.Media.MediaPaths()
	var firstErr error
	for _, mp := range paths {
		// Пустой путь — библиотека не настроена: Walk("") обошёл бы
		// текущую папку и проиндексировал бы лишнее.
		if mp.Path == "" {
			continue
		}
		if err := s.ScanPath(ctx, mp.Path); err != nil {
			log.Printf("Error scanning %s: %v", mp.Path, err)
			if firstErr == nil {
				firstErr = err
			}
		}
	}
	return firstErr
}

func (s *ScannerService) GetScanStatus(key string) *ScanStatus {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if st, ok := s.statuses[key]; ok {
		cp := *st
		return &cp
	}
	return &ScanStatus{Running: false}
}

// maxScanStatuses ограничивает число хранимых статусов: карта чистится при
// завершении сканов, чтобы при длительной работе не расти бесконечно.
const maxScanStatuses = 64

func (s *ScannerService) ScanPath(ctx context.Context, path string) error {
	// Reject concurrent scans of the same path.
	s.mu.Lock()
	if st, ok := s.statuses[path]; ok && st.Running {
		s.mu.Unlock()
		return ErrScanInProgress
	}
	now := time.Now().UTC()
	s.statuses[path] = &ScanStatus{
		Running:   true,
		StartedAt: &now,
	}
	s.mu.Unlock()

	var scanErr error
	seen, err := s.scanPathWalk(ctx, path)
	if err != nil {
		scanErr = err
	} else {
		if err := s.sweepDeleted(ctx, path, seen); err != nil {
			log.Printf("Sweep deleted files for %s: %v", path, err)
		}
	}

	s.mu.Lock()
	st := s.statuses[path]
	st.Running = false
	if scanErr != nil {
		st.Error = scanErr.Error()
	} else {
		st.Error = ""
	}
	s.trimStatusesLocked()
	s.mu.Unlock()

	return scanErr
}

// trimStatusesLocked удаляет завершённые статусы, пока их больше
// maxScanStatuses (самые старые записи — кандидаты на удаление первыми).
func (s *ScannerService) trimStatusesLocked() {
	if len(s.statuses) <= maxScanStatuses {
		return
	}
	overflow := len(s.statuses) - maxScanStatuses
	for key, st := range s.statuses {
		if st.Running {
			continue
		}
		delete(s.statuses, key)
		overflow--
		if overflow <= 0 {
			return
		}
	}
}

// sweepDeleted moves media records under the given path whose files were
// not seen during the scan to the trash (soft delete). Hard-purge здесь
// недопустим: пропажа файла (отвалившийся mount, переименование) не должна
// уничтожать избранное, прогресс и элементы коллекций. Окончательно чистит
// только корзина.
//
// Автовосстановление при возврате файла намеренно не делаем: пользовательская
// корзина файл не удаляет, и скан воскресил бы осознанно удалённые записи.
//
// Uses pagination to avoid loading the entire table at once. Offset-based
// pagination combined with in-place soft deletes would shift the window and
// skip records, so when a page contained deletions we re-request the SAME
// offset: rows that slid into the window are examined before advancing.
func (s *ScannerService) sweepDeleted(ctx context.Context, scanPath string, seen map[string]struct{}) error {
	const pageSize = 200
	offset := 0

	for {
		mediaList, _, err := s.mediaRepo.FindByPathPrefix(ctx, scanPath, pageSize, offset)
		if err != nil {
			return err
		}
		if len(mediaList) == 0 {
			return nil
		}

		deleted := false
		for _, m := range mediaList {
			if _, ok := seen[m.FilePath]; !ok {
				if err := s.mediaRepo.TrashMissing(ctx, m.ID); err != nil {
					log.Printf("Sweep: trash media %d (%s): %v", m.ID, m.FilePath, err)
				} else {
					deleted = true
					log.Printf("Sweep: moved missing file to trash: %s", m.FilePath)
				}
			}
		}

		if deleted {
			// Окно сдвинулось влево — повторяем с тем же offset. Каждая
			// такая итерация удаляет хотя бы одну запись, поэтому цикл
			// гарантированно завершается.
			continue
		}
		offset += pageSize
	}
}

func (s *ScannerService) scanPathWalk(ctx context.Context, scanPath string) (map[string]struct{}, error) {
	seen := make(map[string]struct{})

	err := filepath.Walk(scanPath, func(path string, info os.FileInfo, err error) error {
		// Honour context cancellation so a shutdown/abort does not block.
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		if err != nil {
			// Ошибка доступа/сети — не доказательство отсутствия файла.
			// Прерываем скан без sweep, чтобы не отправить всё поддерево
			// в корзину из-за временно отвалившегося mount.
			if os.IsNotExist(err) {
				return nil
			}
			return fmt.Errorf("walk %s: %w", path, err)
		}

		if info.IsDir() {
			return nil
		}

		// Skip empty files — but still record them in `seen` so sweep does
		// not delete an existing record for a file that temporarily has
		// size 0 (e.g. still being written by another process).
		if info.Size() == 0 {
			existing, ferr := s.mediaRepo.FindByPathBasic(ctx, path)
			if ferr == nil && existing != nil {
				seen[path] = struct{}{}
			}
			return nil
		}

		// Check file extension
		ext := strings.ToLower(filepath.Ext(path))
		if !IsAllowedExtension(ext) {
			return nil
		}

		seen[path] = struct{}{}

		s.scanFile(ctx, path)
		return nil
	})

	return seen, err
}

// FSEvent — событие файловой системы для инкрементальной обработки watcher'ом.
type FSEvent struct {
	Path string
	Op   fsnotify.Op
}

// HandleFSEvents обрабатывает пачку событий файловой системы, накопленных
// watcher'ом за debounce-окно. Create/Write → обработка одного файла
// (создание или обновление записи), Remove/Rename → удаление записи
// (файл исчез). Ошибки отдельных файлов логируются и не прерывают пачку.
func (s *ScannerService) HandleFSEvents(ctx context.Context, events []FSEvent) {
	for _, ev := range events {
		if err := ctx.Err(); err != nil {
			return
		}
		if ev.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
			s.removeMediaForPath(ctx, ev.Path)
			continue
		}
		// Файл мог быть ещё не дописан на момент последнего события —
		// ждём стабилизации размера перед обработкой.
		if !s.waitForFileStable(ctx, ev.Path) {
			continue
		}
		s.scanFile(ctx, ev.Path)
	}
}

// waitForFileStable ждёт, пока размер и mtime файла перестанут меняться
// (файл дописывается копированием/загрузкой). Возвращает false, если файл
// исчез, контекст отменён или стабильность не достигнута за отведённое
// число попыток.
func (s *ScannerService) waitForFileStable(ctx context.Context, path string) bool {
	return waitUntilFileStable(ctx, path, 3, 300*time.Millisecond)
}

// waitUntilFileStable — waitForFileStable с настраиваемыми параметрами
// (вынесено для детерминированного тестирования с малыми интервалами).
func waitUntilFileStable(ctx context.Context, path string, attempts int, interval time.Duration) bool {
	var prevSize int64 = -1
	var prevMod time.Time
	for i := 0; i < attempts; i++ {
		if err := ctx.Err(); err != nil {
			return false
		}
		info, err := os.Stat(path)
		if err != nil {
			if !os.IsNotExist(err) {
				log.Printf("watch scan: stat %s: %v", path, err)
			}
			return false
		}
		if info.Size() == prevSize && info.ModTime().Equal(prevMod) {
			return true
		}
		prevSize = info.Size()
		prevMod = info.ModTime()
		time.Sleep(interval)
	}
	log.Printf("watch scan: file %s did not stabilize, skipping", path)
	return false
}

// removeMediaForPath отправляет запись Media в корзину, если файл исчез
// с диска. Превью/обложки НЕ удаляются: они нужны для восстановления,
// а окончательную чистку делает purge из корзины. Идемпотентно:
// отсутствующая запись — не ошибка.
func (s *ScannerService) removeMediaForPath(ctx context.Context, path string) {
	existing, err := s.mediaRepo.FindByPathBasic(ctx, path)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("watch scan: FindByPath %s: %v", path, err)
		}
		return
	}
	if existing == nil || existing.ID == 0 {
		return
	}
	if existing.DeletedAt.Valid {
		// Уже в корзине: повторный Remove не должен обновлять deleted_at.
		return
	}

	if err := s.mediaRepo.TrashMissing(ctx, existing.ID); err != nil {
		log.Printf("watch scan: trash media %d (%s): %v", existing.ID, path, err)
		return
	}
	log.Printf("watch scan: moved missing file to trash: %s", path)
}

// scanFile обрабатывает один файл: создаёт запись для нового файла или
// обновляет запись изменившегося. Используется и полным сканом (из
// scanPathWalk), и инкрементальной обработкой событий watcher'а.
// Ошибки логируются и не возвращаются: сбой одного файла не должен
// прерывать ни скан, ни пачку событий.
func (s *ScannerService) scanFile(ctx context.Context, path string) {
	s.fileMu.Lock()
	defer s.fileMu.Unlock()
	info, err := os.Stat(path)
	if err != nil {
		// Файл исчез между событием и обработкой — не ошибка.
		return
	}

	// Пустой файл — ещё пишется или битый: запись не трогаем ни в какую
	// сторону (консервативно, как и полный скан).
	if info.Size() == 0 {
		return
	}

	ext := strings.ToLower(filepath.Ext(path))
	if !IsAllowedExtension(ext) {
		return
	}

	// Горячий цикл: дешёвый SELECT без Preload (Metadata/Artists тут
	// не нужны). Полный объект с артистами грузится только для
	// изменившихся файлов — это редкий путь.
	existing, err := s.mediaRepo.FindByPathBasic(ctx, path)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		// A database error is NOT "file is new" — treat it as a scan
		// failure rather than creating a duplicate/malformed record.
		log.Printf("FindByPath error for %s: %v", path, err)
		return
	}
	if err == nil && existing != nil {
		// Корзина: файл с trashed-строкой не импортируем дублем
		// и не обновляем — seen уже помечен вызывающим, sweep
		// (scoped) строку не видит и не тронет.
		//
		// AutoTrashed — системная запись после пропажи файла: если файл
		// вернулся на место, восстанавливаем ту же строку и обновляем её.
		// Так не появляется вторая живая запись на тот же путь, а purge
		// старой строки не удалит вернувшийся файл. Пользовательскую
		// корзину не воскрешаем: файл у неё остаётся на диске намеренно.
		if existing.DeletedAt.Valid {
			if !existing.AutoTrashed {
				return
			}
			if err := s.mediaRepo.RestoreMedia(ctx, existing.ID); err != nil {
				log.Printf("Restore auto-trashed media %d (%s): %v", existing.ID, path, err)
				return
			}
			// updateChangedFile сам перечитает полный объект с Metadata/Artists.
			s.updateChangedFile(ctx, path, info, existing)
			return
		}
		s.updateChangedFile(ctx, path, info, existing)
		return
	}

	s.createNewMedia(ctx, path, info)
}

// backfillDuration заполняет Duration у неизменившегося файла, не
// перезаписывая остальные поля и не трогая связи Artists.
func (s *ScannerService) backfillDuration(ctx context.Context, media *models.Media) {
	duration := s.metaExtractor.probeDuration(ctx, media.FilePath)
	if duration <= 0 {
		return
	}
	media.Duration = duration
	if err := s.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Backfill duration for media %d (%s): %v", media.ID, media.FilePath, err)
	}
}

// updateChangedFile обновляет запись изменившегося файла (quick hash
// не совпал).
func (s *ScannerService) updateChangedFile(ctx context.Context, path string, info os.FileInfo, existing *models.Media) {
	// File exists — check if it changed using quick hash
	qh, err := quickHashFile(ctx, path)
	if err != nil {
		log.Printf("Error quick-hashing file %s: %v", path, err)
		return
	}

	if existing.QuickHash == qh {
		// Файл не менялся, но pHash мог отсутствовать: картинки,
		// проиндексированные до появления pHash, иначе навсегда
		// остались бы невидимыми для дедупа.
		s.backfillImagePHash(ctx, existing)
		// У записей, созданных до фикса аудио-длительности, Duration
		// остался нулевым. Обычный скан их больше не трогает, поэтому
		// добираем только нулевые значения точечным ffprobe.
		if existing.Duration == 0 && existing.Type != models.MediaTypeImage {
			s.backfillDuration(ctx, existing)
		}
		return // unchanged
	}

	// File changed — recompute full hash and update
	fullHash, err := HashFileContext(ctx, path)
	if err != nil {
		log.Printf("Error hashing changed file %s: %v", path, err)
		return
	}

	// Загружаем полный объект (включая Artists), чтобы не затереть
	// ручные правки: пользовательские поля (Title/Year/Artists/
	// Album/Genre) обновляются только если они пустые, технические
	// (хеши, размер, Duration) — всегда. Контракт Update «только
	// непустые поля» делает то же самое на уровне записи.
	changed, loadErr := s.mediaRepo.FindByPath(ctx, path)
	if loadErr == nil && changed != nil {
		existing = changed
	} else if loadErr != nil {
		log.Printf("FindByPath (changed) error for %s: %v", path, loadErr)
	}

	title, year := metadata.ParseFilename(filepath.Base(path))
	existing.Filename = filepath.Base(path)
	existing.FileSize = info.Size()
	existing.FileHash = fullHash
	existing.QuickHash = qh
	if existing.Title == "" {
		existing.Title = title
	}
	if existing.Year == 0 {
		existing.Year = year
	}

	// Re-extract metadata from changed file. Не затираем ручные
	// правки: поля заполняются только при пустых текущих значениях.
	if fileMeta := s.metaExtractor.ExtractFromFileContext(ctx, path); fileMeta != nil {
		if fileMeta.Duration > 0 {
			existing.Duration = fileMeta.Duration
		}
		if len(existing.Artists) == 0 && fileMeta.Artist != "" {
			existing.Artists = []models.Artist{{Name: fileMeta.Artist}}
		}
		if existing.Album == "" && fileMeta.Album != "" {
			existing.Album = fileMeta.Album
		}
		if existing.Genre == "" && fileMeta.Genre != "" {
			existing.Genre = fileMeta.Genre
		}
		// Размеры кадра — ТЕХНИЧЕСКИЕ поля: они перезаписываются
		// всегда, в отличие от пользовательских (title/artist/album/
		// genre), которые заполняются только при пустых значениях.
		// Файл по тому же пути мог быть заменён на другой — с другим
		// разрешением, и старые пропорции вели бы к неверной ориентации
		// в плеере.
		ApplyVideoDimensions(existing, fileMeta)
	}

	// Regenerate thumbnail for changed file. В БД сохраняем
	// относительный URL — фронтенд строит полный адрес сам.
	thumbPath := s.thumbService.GenerateWithContext(ctx, existing.ID, path)
	if thumbPath != "" {
		existing.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", existing.ID)
	}
	if existing.Type == models.MediaTypeImage {
		if thumbPath == "" {
			// ffmpeg при раннем сбое декодирования оставляет старый
			// файл превью на диске. Он описывает прежнюю картинку —
			// удаляем, иначе бэкфилл посчитает pHash по устаревшему
			// превью и дедуп начнёт врать.
			s.thumbService.RemoveThumbnail(existing.ID)
		}
		// Хэш пересчитываем всегда: у изменённого файла старое значение
		// уже не описывает картинку. Пустое превью обнуляет хэш.
		s.updateImagePHash(ctx, existing.ID, thumbPath)
	}

	// Extract embedded cover art (if file has one). У картинки «обложка» —
	// это сам файл, отдельный арт из неё извлекать не нужно.
	if existing.Type != models.MediaTypeImage {
		if coverPath := s.thumbService.ExtractCoverContext(ctx, existing.ID, path); coverPath != "" {
			existing.CoverURL = fmt.Sprintf("/api/media/%d/cover", existing.ID)
		}
	}

	if err := s.mediaRepo.Update(ctx, existing); err != nil {
		log.Printf("Error updating changed file %s: %v", path, err)
	} else {
		log.Printf("Updated changed file: %s", path)
	}
}

// createNewMedia создаёт запись для нового файла (полный хэш, проверка
// дубликатов, ffprobe, метаданные, миниатюра).
func (s *ScannerService) createNewMedia(ctx context.Context, path string, info os.FileInfo) {
	// New file — compute both hashes
	qh, err := quickHashFile(ctx, path)
	if err != nil {
		log.Printf("Error quick-hashing file %s: %v", path, err)
		return
	}

	hash, err := HashFileContext(ctx, path)
	if err != nil {
		log.Printf("Error hashing file %s: %v", path, err)
		return
	}

	// Check if file with same hash already exists
	duplicate, err := s.mediaRepo.FindByHash(ctx, hash)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		// A database error is NOT "no duplicate" — treat it as a scan
		// failure rather than creating a duplicate record.
		log.Printf("FindByHash error for %s: %v", path, err)
		return
	}
	if duplicate != nil && duplicate.ID != 0 {
		log.Printf("Skipping duplicate: %s (same hash as %s)", path, duplicate.FilePath)
		return
	}

	// Parse filename for metadata
	title, year := metadata.ParseFilename(filepath.Base(path))

	// Тип определяется по расширению, а для видео/аудио уточняется
	// пробой. Для картинок ffprobe не используется для типа: JPEG/PNG
	// отдаёт видеопоток и увёл бы файл в видео.
	detectedType := determineMediaTypeByExt(path)

	// Probe once for video metadata. Inherit from the scan context so a
	// cancelled scan also cancels the ffprobe call. Картинкам проба нужна
	// только ради Width/Height — тип по ней не меняем.
	probeCtx, probeCancel := context.WithTimeout(ctx, 10*time.Second)
	probeData, probeErr := ffprobe.ProbeURL(probeCtx, path)
	probeCancel()

	if probeErr == nil && detectedType != models.MediaTypeImage {
		detectedType = DetermineMediaTypeFromProbe(probeData)
	} else if probeErr != nil {
		log.Printf("Probe failed for %s: %v", path, probeErr)
	}

	media := &models.Media{
		Title:     title,
		Filename:  filepath.Base(path),
		Year:      year,
		Type:      detectedType,
		FilePath:  path,
		FileSize:  info.Size(),
		FileHash:  hash,
		QuickHash: qh,
	}

	if err := s.mediaRepo.Create(ctx, media); err != nil {
		log.Printf("Error creating media record for %s: %v", path, err)
		return
	}

	// Extract metadata from file (duration, tags, etc.)
	// Reuse probe data when available to avoid a second ffprobe call.
	if fileMeta := s.metaExtractor.ExtractFromFileContext(ctx, path, probeData); fileMeta != nil {
		if media.Duration == 0 && fileMeta.Duration > 0 {
			media.Duration = fileMeta.Duration
		}
		if len(media.Artists) == 0 && fileMeta.Artist != "" {
			media.Artists = []models.Artist{{Name: fileMeta.Artist}}
		}
		if media.Album == "" && fileMeta.Album != "" {
			media.Album = fileMeta.Album
		}
		if media.Genre == "" && fileMeta.Genre != "" {
			media.Genre = fileMeta.Genre
		}
		if media.Width == 0 && fileMeta.Width > 0 {
			media.Width = fileMeta.Width
		}
		if media.Height == 0 && fileMeta.Height > 0 {
			media.Height = fileMeta.Height
		}
		if fileMeta.Title != "" {
			media.Title = fileMeta.Title
		}
		if detectedType.IsAudio() && len(media.Artists) > 0 {
			desc := media.Artists[0].Name
			if media.Album != "" {
				desc += " — " + media.Album
			}
			media.Description = desc
		}
		if err := s.mediaRepo.Update(ctx, media); err != nil {
			log.Printf("Error updating media metadata for %s: %v", path, err)
		}
	}

	// Generate thumbnail. В БД сохраняем относительный URL — фронтенд
	// строит полный адрес сам.
	thumbPath := s.thumbService.GenerateWithContext(ctx, media.ID, path)
	if thumbPath != "" {
		media.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", media.ID)
		if err := s.mediaRepo.Update(ctx, media); err != nil {
			log.Printf("Error updating media thumbnail for %s: %v", path, err)
		}
	}

	// pHash считается с превью: похожие мемы пропускаем молча, как и
	// точные дубли (файл на диске не удаляем — им распоряжается владелец
	// библиотеки).
	if detectedType == models.MediaTypeImage && thumbPath != "" {
		phash, hashErr := ImagePHash(thumbPath)
		if hashErr != nil {
			log.Printf("image phash for %s: %v", path, hashErr)
			return
		}
		similar, findErr := FindSimilarImage(ctx, s.mediaRepo, phash, media.ID)
		if findErr != nil {
			log.Printf("find similar image for %s: %v", path, findErr)
		} else if similar != nil {
			log.Printf("Skipping similar image: %s (matches media %d %q)", path, similar.ID, similar.Title)
			if err := s.mediaRepo.PurgeMedia(ctx, media.ID); err != nil {
				log.Printf("remove similar image record %d: %v", media.ID, err)
			}
			s.thumbService.RemoveThumbnail(media.ID)
			return
		}
		if err := s.mediaRepo.SetPHash(ctx, media.ID, phash); err != nil {
			log.Printf("save image phash for %s: %v", path, err)
		}
	}
}

// updateImagePHash пересчитывает pHash по превью. Пустое превью обнуляет
// хэш, чтобы изменённый файл не находился по старому значению.
func (s *ScannerService) updateImagePHash(ctx context.Context, mediaID uint, thumbPath string) {
	phash := int64(0)
	if thumbPath != "" {
		hash, err := ImagePHash(thumbPath)
		if err != nil {
			log.Printf("image phash for media %d: %v", mediaID, err)
		} else {
			phash = hash
		}
	}
	if err := s.mediaRepo.SetPHash(ctx, mediaID, phash); err != nil {
		log.Printf("save image phash for media %d: %v", mediaID, err)
	}
}

// backfillImagePHash досчитывает pHash для неизменившейся картинки.
// Превью уже есть на диске; оригинал повторно не читаем.
func (s *ScannerService) backfillImagePHash(ctx context.Context, media *models.Media) {
	if media.Type != models.MediaTypeImage || media.PHash != 0 {
		return
	}
	thumbPath := s.thumbService.GetPath(media.ID)
	if _, err := os.Stat(thumbPath); err != nil {
		return
	}
	phash, err := ImagePHash(thumbPath)
	if err != nil {
		log.Printf("backfill image phash for media %d: %v", media.ID, err)
		return
	}
	if phash == 0 {
		return
	}
	if err := s.mediaRepo.SetPHash(ctx, media.ID, phash); err != nil {
		log.Printf("save backfilled image phash for media %d: %v", media.ID, err)
	}
}

// HashFile computes full SHA-256 of a file (без контекста — для внешних
// вызовов вне сканера, например upload handler).
func HashFile(path string) (string, error) {
	return HashFileContext(context.Background(), path)
}

// HashFileContext computes full SHA-256 of a file, honouring ctx cancellation.
func HashFileContext(ctx context.Context, path string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, contextReader{ctx: ctx, r: f}); err != nil {
		return "", err
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}

// contextReader проверяет отмену контекста перед каждым чтением, чтобы
// хеширование большого файла прерывалось при отмене скана.
type contextReader struct {
	ctx context.Context
	r   io.Reader
}

func (cr contextReader) Read(p []byte) (int, error) {
	select {
	case <-cr.ctx.Done():
		return 0, cr.ctx.Err()
	default:
	}
	return cr.r.Read(p)
}

// contextReadSeeker — contextReader с поддержкой Seek (для tag.ReadFrom).
type contextReadSeeker struct {
	contextReader
}

func (crs contextReadSeeker) Seek(offset int64, whence int) (int64, error) {
	rs, ok := crs.r.(io.ReadSeeker)
	if !ok {
		return 0, errors.New("underlying reader is not a ReadSeeker")
	}
	return rs.Seek(offset, whence)
}

// quickHashFile computes a fast hash from the first and last 1MB of a file
// plus the file size. This is sufficient for detecting file changes without
// reading the entire file.
func quickHashFile(ctx context.Context, path string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return "", err
	}

	h := sha256.New()

	// Hash file size
	sizeBuf := make([]byte, 8)
	size := stat.Size()
	for i := 7; i >= 0; i-- {
		sizeBuf[i] = byte(size)
		size >>= 8
	}
	h.Write(sizeBuf)

	// Hash first chunk.
	head := make([]byte, quickHashChunk)
	n, err := io.ReadFull(contextReader{ctx: ctx, r: f}, head)
	if n > 0 {
		h.Write(head[:n])
	}
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return "", err
	}

	// Hash last chunk. Любой файл больше 1MB получает отдельное чтение
	// хвоста: иначе байты [1MB; конец) не попали бы в хеш, и изменение
	// файла 1–2 МБ при неизменном размере не детектировалось бы.
	fileSize := stat.Size()
	if fileSize > int64(quickHashChunk) {
		if _, err := f.Seek(-int64(quickHashChunk), io.SeekEnd); err != nil {
			return "", err
		}
		tail := make([]byte, quickHashChunk)
		n, err := io.ReadFull(contextReader{ctx: ctx, r: f}, tail)
		if n > 0 {
			h.Write(tail[:n])
		}
		if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
			return "", err
		}
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}

// DetermineMediaType probes the file with ffprobe to detect its real type.
func DetermineMediaType(filePath string) models.MediaType {
	// Картинки определяем по расширению до пробы: ffprobe видит в них
	// видеопоток и вернул бы video.
	ext := strings.ToLower(filepath.Ext(filePath))
	if imageExtensions[ext] {
		return models.MediaTypeImage
	}

	// Голое имя без директории (несохранённый аплоад из хендлера):
	// пробовать ffprobe не на чем — сразу fallback по расширению,
	// без заведомо провальной пробы и лог-спама.
	if filepath.Dir(filePath) == "." {
		return determineMediaTypeByExt(filePath)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	data, err := ffprobe.ProbeURL(ctx, filePath)
	if err != nil {
		// Fallback to extension-based detection.
		log.Printf("DetermineMediaType: ffprobe %s: %v, using extension fallback", filePath, err)
		return determineMediaTypeByExt(filePath)
	}

	return DetermineMediaTypeFromProbe(data)
}

// determineMediaTypeByExt is the fallback when ffprobe is unavailable.
func determineMediaTypeByExt(filePath string) models.MediaType {
	ext := strings.ToLower(filepath.Ext(filePath))
	switch {
	case imageExtensions[ext]:
		return models.MediaTypeImage
	case audioExtensions[ext]:
		return models.MediaTypeAudio
	default:
		return models.MediaTypeVideo
	}
}
