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
)

func IsAllowedExtension(ext string) bool {
	return videoExtensions[ext] || audioExtensions[ext]
}

type ScannerService struct {
	mediaRepo     repository.MediaRepository
	config        *config.Config
	metaExtractor *MetadataExtractor
	thumbService  *ThumbnailService

	mu       sync.RWMutex
	statuses map[string]*ScanStatus
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
		if err := s.ScanPath(ctx, mp.Path, mp.Type); err != nil {
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

func (s *ScannerService) ScanPath(ctx context.Context, path string, mediaType models.MediaType) error {
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
	seen, err := s.scanPathWalk(ctx, path, mediaType)
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

// sweepDeleted removes media records under the given path whose files were
// not seen during the scan (i.e. deleted from disk).
// Uses pagination to avoid loading the entire table at once. Offset-based
// pagination combined with in-place deletes would shift the window and skip
// records, so when a page contained deletions we re-request the SAME offset:
// rows that slid into the window are examined before advancing.
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
				if err := s.mediaRepo.Delete(ctx, m.ID); err != nil {
					log.Printf("Sweep: delete media %d (%s): %v", m.ID, m.FilePath, err)
				} else {
					deleted = true
					log.Printf("Sweep: removed missing file: %s", m.FilePath)
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

func (s *ScannerService) scanPathWalk(ctx context.Context, scanPath string, mediaType models.MediaType) (map[string]struct{}, error) {
	seen := make(map[string]struct{})

	err := filepath.Walk(scanPath, func(path string, info os.FileInfo, err error) error {
		// Honour context cancellation so a shutdown/abort does not block.
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		if err != nil {
			log.Printf("Walk error for %s: %v", path, err)
			return nil
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

		// Горячий цикл: дешёвый SELECT без Preload (Metadata/Artists тут
		// не нужны). Полный объект с артистами грузится только для
		// изменившихся файлов — это редкий путь.
		existing, err := s.mediaRepo.FindByPathBasic(ctx, path)
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			// A database error is NOT "file is new" — treat it as a scan
			// failure rather than creating a duplicate/malformed record.
			log.Printf("FindByPath error for %s: %v", path, err)
			return nil
		}
		if err == nil && existing != nil {
			// File exists — check if it changed using quick hash
			qh, err := quickHashFile(ctx, path)
			if err != nil {
				log.Printf("Error quick-hashing file %s: %v", path, err)
				return nil
			}

			if existing.QuickHash == qh {
				return nil // unchanged
			}

			// File changed — recompute full hash and update
			fullHash, err := HashFileContext(ctx, path)
			if err != nil {
				log.Printf("Error hashing changed file %s: %v", path, err)
				return nil
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
			}

			// Regenerate thumbnail for changed file. В БД сохраняем
			// относительный URL — фронтенд строит полный адрес сам.
			if thumbPath := s.thumbService.GenerateWithContext(ctx, existing.ID, path); thumbPath != "" {
				existing.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", existing.ID)
			}

			// Extract embedded cover art (if file has one).
			if coverPath := s.thumbService.ExtractCoverContext(ctx, existing.ID, path); coverPath != "" {
				existing.CoverURL = fmt.Sprintf("/api/media/%d/cover", existing.ID)
			}

			if err := s.mediaRepo.Update(ctx, existing); err != nil {
				log.Printf("Error updating changed file %s: %v", path, err)
			} else {
				log.Printf("Updated changed file: %s", path)
			}
			return nil
		}

		// New file — compute both hashes
		qh, err := quickHashFile(ctx, path)
		if err != nil {
			log.Printf("Error quick-hashing file %s: %v", path, err)
			return nil
		}

		hash, err := HashFileContext(ctx, path)
		if err != nil {
			log.Printf("Error hashing file %s: %v", path, err)
			return nil
		}

		// Check if file with same hash already exists
		duplicate, err := s.mediaRepo.FindByHash(ctx, hash)
		if err == nil && duplicate != nil {
			log.Printf("Skipping duplicate: %s (same hash as %s)", path, duplicate.FilePath)
			return nil
		}

		// Parse filename for metadata
		title, year := metadata.ParseFilename(filepath.Base(path))

		// Probe once for both media type and video metadata. Inherit from the
		// scan context so a cancelled scan also cancels the ffprobe call.
		probeCtx, probeCancel := context.WithTimeout(ctx, 10*time.Second)
		probeData, probeErr := ffprobe.ProbeURL(probeCtx, path)
		probeCancel()

		// Use a local `detectedType` to avoid shadowing the `mediaType`
		// parameter — the parameter is the user-provided hint, while this
		// variable holds the actual detected type from probing.
		detectedType := models.MediaTypeVideo
		if probeErr == nil {
			detectedType = DetermineMediaTypeFromProbe(probeData)
		} else {
			log.Printf("Probe failed for %s: %v, using extension fallback", path, probeErr)
			detectedType = determineMediaTypeByExt(path)
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
			return nil
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
		if thumbPath := s.thumbService.GenerateWithContext(ctx, media.ID, path); thumbPath != "" {
			media.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", media.ID)
			if err := s.mediaRepo.Update(ctx, media); err != nil {
				log.Printf("Error updating media thumbnail for %s: %v", path, err)
			}
		}

		return nil
	})

	return seen, err
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
	if audioExtensions[ext] {
		return models.MediaTypeAudio
	}
	return models.MediaTypeVideo
}
