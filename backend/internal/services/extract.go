package services

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"gopkg.in/vansante/go-ffprobe.v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
)

// Статусы задания извлечения (значения сериализуются в JSON API как есть,
// совпадают со статусами upload-очереди — фронт переиспользует модель).
const (
	ExtractJobQueued     = "queued"
	ExtractJobProcessing = "processing"
	ExtractJobDone       = "done"
	ExtractJobError      = "error"
	// extractJobCancelled — внутренний статус отменённого задания. Наружу
	// не возвращается: задание удаляется из очереди при отмене.
	extractJobCancelled = "cancelled"
)

const (
	DefaultExtractQueueWorkers = 1
	DefaultExtractQueueLimit   = 20
)

// extractJobTTL — сколько терминальное задание (done/error) хранится в
// карте (фронт опрашивает статус; мгновенно чистить нельзя).
const extractJobTTL = time.Hour

// maxExtractTimeout — потолок ffmpeg-таймаута: без него 3-часовой фильм
// при кодировании держал бы воркер ~9 часов.
const maxExtractTimeout = time.Hour

// maxKeptExtractJobs — жёсткий потолок числа хранимых заданий.
const maxKeptExtractJobs = 200

// extractSweepInterval — период фоновой чистки терминальных заданий.
const extractSweepInterval = 10 * time.Minute

var (
	ErrExtractQueueFull   = errors.New("extract queue is full")
	ErrExtractJobNotFound = errors.New("extract job not found")
	ErrExtractJobDone     = errors.New("extract job already done")
	// errExtractFileExists — dst занят на момент коммита (см. commitFile).
	errExtractFileExists = errors.New("destination file exists")
)

// extractTarget — куда класть извлечённую дорожку. Stream copy сохраняет
// исходное качество 1:1 и идёт со скоростью IO; encodeFLAC — lossless-
// фолбэк для кодеков, которые нельзя скопировать в аудио-контейнер.
// format — явный muxer для флага -f: угадывать контейнер по расширению
// tmp-файла (.part-N) ffmpeg не умеет и падает с Invalid argument.
type extractTarget struct {
	ext        string
	format     string
	encodeFLAC bool
}

// extractTargetFor подбирает контейнер по аудиокодеку из ffprobe.
// Неизвестный кодек — FLAC-encode: максимальное качество вместо падения.
func extractTargetFor(codec string) extractTarget {
	switch strings.ToLower(codec) {
	case "aac":
		return extractTarget{ext: ".m4a", format: "mp4"}
	case "mp3":
		return extractTarget{ext: ".mp3", format: "mp3"}
	case "opus":
		return extractTarget{ext: ".opus", format: "opus"}
	case "vorbis":
		return extractTarget{ext: ".ogg", format: "ogg"}
	case "flac":
		return extractTarget{ext: ".flac", format: "flac"}
	case "alac":
		return extractTarget{ext: ".m4a", format: "mp4"}
	case "wav":
		return extractTarget{ext: ".wav", format: "wav"}
	case "ac3", "eac3", "dts", "dts_hd", "truehd":
		return extractTarget{ext: ".flac", format: "flac", encodeFLAC: true}
	default:
		if strings.HasPrefix(strings.ToLower(codec), "pcm_") {
			return extractTarget{ext: ".wav", format: "wav"}
		}
		return extractTarget{ext: ".flac", format: "flac", encodeFLAC: true}
	}
}

// ExtractJob — задание извлечения аудиодорожки из видео. Все поля доступны
// только под mutex'ом сервиса (воркер и хендлеры разделяют объект).
// ID — из БД (extract_tasks.id, стабилен между рестартами).
type ExtractJob struct {
	ID        uint
	Status    string
	Error     string
	MediaID   uint
	sourceID  uint
	createdAt time.Time
	// outPath — итоговый путь уже закоммиченного результата. До успешного
	// commitFile остаётся пустым: fail() не должен удалять чужой файл.
	outPath string
	// jobCancel убивает запущенный ffmpeg. Выставляется воркером при
	// старте обработки; Cancel дёргает под локом.
	jobCancel context.CancelFunc
}

// ExtractService — очередь извлечения аудио с персистентными строками
// (extract_tasks). Механика зеркалит UploadQueue (канал + карта + sweep
// + отмена): семантика другая (вход — mediaId, а не файл), поэтому общая
// абстракция дала бы ложную общность.
type ExtractService struct {
	mu    sync.Mutex
	jobs  map[uint]*ExtractJob
	queue chan *ExtractJob
	limit int
	// enqueueMu сериализует постановки: без него параллельные Enqueue
	// одного источника одновременно проходят проверку дедупа и плодят
	// дубли (check-then-act на карте + БД).
	enqueueMu sync.Mutex
	ctx       context.Context
	cancel    context.CancelFunc
	wg        sync.WaitGroup
	media     repository.MediaRepository
	tasks     repository.ExtractTaskRepository
	thumbSvc  *ThumbnailService
	extract   *MetadataExtractor
	audioPath string
	// available — ffmpeg+ffprobe найдены при создании. Без них сервер
	// стартует, но хендлер отвечает 503 (см. Available).
	available bool
	// probeFn/runFFmpegFn — точки подмены для тестов. В продакшене nil:
	// используются probeAudioCodec и runFFmpeg. Нужны, чтобы проверять
	// порядок cleanup без реальных ffmpeg/ffprobe (их может не быть в CI).
	probeFn     func(context.Context, string) (string, float64, error)
	runFFmpegFn func(context.Context, string, string, extractTarget, float64) error
}

func NewExtractService(
	ctx context.Context,
	mediaRepo repository.MediaRepository,
	tasks repository.ExtractTaskRepository,
	thumbSvc *ThumbnailService,
	audioPath string,
	workers, limit int,
) *ExtractService {
	if workers < 0 {
		workers = DefaultExtractQueueWorkers
	}
	if limit <= 0 {
		limit = DefaultExtractQueueLimit
	}
	qctx, cancel := context.WithCancel(ctx)
	// Наличие бинарников — флагом, а не fail-fast конструктора: сервер
	// обязан стартовать и без ffmpeg (библиотека работает), а хендлер
	// отдаёт 503 по Available(). Fail-fast в app.go уронил бы и app-тесты
	// в окружениях без ffmpeg.
	_, ffmpegErr := exec.LookPath("ffmpeg")
	_, ffprobeErr := exec.LookPath("ffprobe")
	if ffmpegErr != nil || ffprobeErr != nil {
		log.Printf("extract queue: ffmpeg/ffprobe not in PATH, extraction jobs will fail")
	}
	q := &ExtractService{
		jobs:      make(map[uint]*ExtractJob),
		queue:     make(chan *ExtractJob, limit),
		limit:     limit,
		ctx:       qctx,
		cancel:    cancel,
		media:     mediaRepo,
		tasks:     tasks,
		thumbSvc:  thumbSvc,
		extract:   NewMetadataExtractor(),
		audioPath: audioPath,
		available: ffmpegErr == nil && ffprobeErr == nil,
	}
	for i := 0; i < workers; i++ {
		q.wg.Add(1)
		go q.worker()
	}
	q.wg.Add(1)
	go q.sweepLoop()
	q.recoverInterrupted()
	return q
}

// recoverInterrupted поднимает незавершённые строки из БД (следствие
// рестарта посреди обработки): сбрасывает processing в queued,
// пересоздаёт in-memory записи. ID раздаёт БД, переиспользования нет.
// Отправка в канал — отдельной горутиной с блокировкой: unfinished
// может быть больше буфера, а конструктор блокироваться не должен.
func (q *ExtractService) recoverInterrupted() {
	unfinished, err := q.tasks.FindUnfinished(context.Background(), ExtractJobQueued, ExtractJobProcessing)
	if err != nil {
		log.Printf("extract queue: load unfinished jobs: %v", err)
		return
	}
	var ids []uint
	for _, row := range unfinished {
		if row.Status == ExtractJobProcessing {
			if err := q.tasks.SetStatus(context.Background(), row.ID, ExtractJobQueued, "", 0); err != nil {
				log.Printf("extract queue: reset job %d: %v", row.ID, err)
				continue
			}
		}
		q.mu.Lock()
		q.jobs[row.ID] = &ExtractJob{
			ID:        row.ID,
			Status:    ExtractJobQueued,
			sourceID:  row.SourceMediaID,
			createdAt: row.CreatedAt,
		}
		q.mu.Unlock()
		ids = append(ids, row.ID)
	}
	if len(ids) == 0 {
		return
	}
	log.Printf("extract queue: recovered %d interrupted job(s)", len(ids))
	q.wg.Add(1)
	go q.recoverQueue(ids)
}

func (q *ExtractService) recoverQueue(ids []uint) {
	defer q.wg.Done()
	for _, id := range ids {
		q.mu.Lock()
		job, ok := q.jobs[id]
		q.mu.Unlock()
		if !ok {
			continue
		}
		select {
		case q.queue <- job:
		case <-q.ctx.Done():
			return
		}
	}
}

// Available сообщает, есть ли ffmpeg+ffprobe: без них извлечение
// невозможно, и хендлер отвечает 503 вместо постановки заведомо
// мёртвого джоба.
func (q *ExtractService) Available() bool {
	return q.available
}

// saveStatus пишет переход в БД best-effort: недоступная БД ломает
// и остальной сервер, поэтому воркер продолжает in-memory.
func (q *ExtractService) saveStatus(job *ExtractJob) {
	q.mu.Lock()
	id, status, errMsg, mediaID := job.ID, job.Status, job.Error, job.MediaID
	q.mu.Unlock()
	if err := q.tasks.SetStatus(context.Background(), id, status, errMsg, mediaID); err != nil {
		log.Printf("extract queue: save task %d: %v", id, err)
	}
}

// Enqueue ставит задание в очередь и возвращает его ID. Повторный POST
// того же видео, пока прошлый джоб летит (queued/processing), отдаёт ID
// существующего задания вместо нового: без дедупа параллельные запросы
// плодили бы по ffmpeg на один источник.
func (q *ExtractService) Enqueue(sourceID uint) (uint, error) {
	// Сериализация всего check-then-act: карта + БД + вставка.
	q.enqueueMu.Lock()
	defer q.enqueueMu.Unlock()

	q.mu.Lock()
	for id, job := range q.jobs {
		if job.sourceID == sourceID &&
			(job.Status == ExtractJobQueued || job.Status == ExtractJobProcessing) {
			q.mu.Unlock()
			return id, nil
		}
	}
	q.mu.Unlock()
	// Дыра после рестарта: поднятые задания уже в карте выше, но на
	// всякий случай проверяем и БД (один дешёвый запрос на постановку).
	if active, err := q.tasks.FindActiveBySource(context.Background(), sourceID, ExtractJobQueued, ExtractJobProcessing); err == nil {
		return active.ID, nil
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		log.Printf("extract queue: find active job: %v", err)
	}
	row := &models.ExtractTask{SourceMediaID: sourceID, Status: ExtractJobQueued}
	if err := q.tasks.Create(context.Background(), row); err != nil {
		return 0, err
	}
	job := &ExtractJob{
		ID:        row.ID,
		Status:    ExtractJobQueued,
		sourceID:  sourceID,
		createdAt: row.CreatedAt,
	}
	q.mu.Lock()
	q.jobs[job.ID] = job
	q.mu.Unlock()

	select {
	case q.queue <- job:
		return job.ID, nil
	default:
		q.mu.Lock()
		delete(q.jobs, job.ID)
		q.mu.Unlock()
		if err := q.tasks.Delete(context.Background(), job.ID); err != nil {
			log.Printf("extract queue: delete overflowed job %d: %v", job.ID, err)
		}
		return 0, ErrExtractQueueFull
	}
}

// Get возвращает копию статуса задания. ok=false — задания нет.
// Сначала карта, затем БД: завершённые (но ещё не выметенные) строки
// переживают даже вытеснение из памяти.
func (q *ExtractService) Get(id uint) (status, errMsg string, mediaID uint, ok bool) {
	q.mu.Lock()
	job, found := q.jobs[id]
	var st, em string
	var mid uint
	if found {
		st, em, mid = job.Status, job.Error, job.MediaID
	}
	q.mu.Unlock()
	if found {
		return st, em, mid, true
	}
	row, err := q.tasks.Get(context.Background(), id)
	if err != nil {
		return "", "", 0, false
	}
	return row.Status, row.Error, row.MediaID, true
}

// Cancel отменяет задание, если оно ещё не завершено: убивает запущенный
// ffmpeg через per-job контекст, удаляет задание из карты и строку из БД;
// файл и запись Media (если созданы) подчищает воркер на ближайшей проверке
// отмены. Done-задание отменить нельзя — ErrExtractJobDone. После отмены
// клиент увидит 404 на статусе (запись удалена) — отмену он отличает по своему
// локальному флагу, а не по коду.
func (q *ExtractService) Cancel(id uint) error {
	q.mu.Lock()
	job, found := q.jobs[id]
	if !found {
		q.mu.Unlock()
		return ErrExtractJobNotFound
	}
	if job.Status == ExtractJobDone {
		q.mu.Unlock()
		return ErrExtractJobDone
	}
	job.Status = extractJobCancelled
	if job.jobCancel != nil {
		// Убиваем запущенный ffmpeg: воркер увидит отмену на ближайшей
		// проверке и подчистит частичный результат сам.
		job.jobCancel()
	}
	delete(q.jobs, id)
	q.mu.Unlock()
	if err := q.tasks.Delete(context.Background(), id); err != nil {
		log.Printf("extract queue: delete cancelled job %d: %v", id, err)
	}

	// Файла на этом этапе может ещё не быть (задание в queued), поэтому
	// чистить здесь нечего — пути знает только воркер.
	return nil
}

func (q *ExtractService) Stop() {
	q.cancel()
	q.wg.Wait()
}

func (q *ExtractService) worker() {
	defer q.wg.Done()
	for {
		select {
		case job := <-q.queue:
			q.safeProcess(job)
		case <-q.ctx.Done():
			return
		}
	}
}

func (q *ExtractService) safeProcess(job *ExtractJob) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("extract queue: worker panic for job %d: %v", job.ID, r)
			q.fail(job, fmt.Errorf("worker panic: %v", r), "Failed to extract audio")
		}
	}()
	q.process(job)
}

// process выполняет цепочку: видео → аудиокодек → ffmpeg во временный
// файл → коммит rename → запись Media со связкой → метаданные/обложка.
func (q *ExtractService) process(job *ExtractJob) {
	q.mu.Lock()
	if job.Status != extractJobCancelled {
		job.Status = ExtractJobProcessing
		job.Error = ""
	}
	sourceID := job.sourceID
	earlyCancelled := job.Status == extractJobCancelled
	// Per-job контекст: отмена убивает именно этот ffmpeg, а не всю
	// очередь. Производный от q.ctx — Stop гасит всё разом.
	jobCtx, jobCancel := context.WithCancel(q.ctx)
	job.jobCancel = jobCancel
	q.mu.Unlock()
	defer jobCancel()
	if !earlyCancelled {
		q.saveStatus(job)
	} else {
		// Отмена пришла, пока задание ждало воркера: файл ещё не создан,
		// чистить нечего.
		return
	}

	source, err := q.media.FindByID(jobCtx, sourceID)
	if err != nil {
		q.fail(job, err, "Source media not found")
		return
	}
	if !source.Type.IsVideo() {
		q.fail(job, fmt.Errorf("media %d is not a video", sourceID), "Source must be a video")
		return
	}

	// Повтор после краха в окне между Create и Done: трек со связкой уже
	// записан, извлекать заново нечего — иначе ffmpeg гонялся бы впустую,
	// а FindByHash нашёл бы собственный сироту прошлого прогона и задание
	// завершилось бы ложным «File already exists» при успехе.
	// Зеркалит проверку хендлера: повторный POST отдаёт 200 с треком.
	if existing, err := q.media.FindBySourceMediaID(jobCtx, sourceID); err == nil && existing != nil && existing.ID != 0 {
		q.mu.Lock()
		job.MediaID = existing.ID
		job.Status = ExtractJobDone
		job.Error = ""
		q.mu.Unlock()
		q.saveStatus(job)
		return
	} else if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		q.fail(job, err, "Failed to check existing track")
		return
	}

	base := source.Title
	if base == "" {
		base = strings.TrimSuffix(source.Filename, filepath.Ext(source.Filename))
	}
	// Ранняя валидация имени до probe/ffmpeg: траверсал и control-символы
	// отсекаются без тяжёлых вызовов (и без ffmpeg в тестах).
	if _, err := SanitizeFilename(base + ".tmp"); err != nil {
		q.fail(job, fmt.Errorf("bad title for media %d", sourceID), "Invalid filename")
		return
	}

	codec, duration, err := q.probeAudio(jobCtx, source.FilePath)
	if err != nil {
		q.fail(job, err, "Failed to probe audio stream")
		return
	}
	if codec == "" {
		q.fail(job, fmt.Errorf("no audio stream in %s", source.FilePath), "Video has no audio stream")
		return
	}
	target := extractTargetFor(codec)

	filename, err := SanitizeFilename(base + target.ext)
	if err != nil || filename == "" {
		q.fail(job, fmt.Errorf("bad filename for media %d", sourceID), "Invalid filename")
		return
	}
	filename = truncateFilename(filename)
	dstPath := filepath.Join(q.audioPath, filename)
	if !IsSubPath(q.audioPath, dstPath) {
		q.fail(job, fmt.Errorf("path escape for media %d", sourceID), "Invalid filename")
		return
	}
	if err := os.MkdirAll(q.audioPath, 0755); err != nil {
		q.fail(job, err, "Failed to create directory")
		return
	}
	// job.outPath до commitFile НЕ выставляем: там ещё нет нашего файла,
	// а cleanupJob по outPath удаляет путь. Иначе ошибка ffmpeg/хэша
	// сносила бы чужой существующий файл с тем же именем.
	//
	// Частичный результат не должен светиться в сканируемой директории:
	// пишем в tmp и коммитим rename в конце. Имя уникально на джоб —
	// параллельные ffmpeg не делят файл даже при workers>1.
	tmpPath := fmt.Sprintf("%s.part-%d", dstPath, job.ID)
	// Best-effort проверка места: исходник плюс запас на FLAC-фолбэк.
	if err := checkDiskSpace(q.audioPath, source.FileSize); err != nil {
		q.fail(job, err, "Not enough disk space")
		return
	}

	// Остаток прошлого прогона после краха: ffmpeg с флагом -n отказался
	// бы перезаписывать, и поднятое задание упало бы сразу. Имя уникально
	// на джоб (.part-<id>), чужое не сносим.
	os.Remove(tmpPath)
	if err := q.runFFmpegForJob(jobCtx, source.FilePath, tmpPath, target, duration); err != nil {
		os.Remove(tmpPath)
		if cancelled := q.markCancelled(job); cancelled {
			return
		}
		q.fail(job, err, "Failed to extract audio")
		return
	}
	if cancelled := q.markCancelled(job); cancelled {
		os.Remove(tmpPath)
		return
	}

	hash, err := HashFileContext(jobCtx, tmpPath)
	if err != nil {
		os.Remove(tmpPath)
		if cancelled := q.markCancelled(job); cancelled {
			return
		}
		q.fail(job, err, "Failed to hash file")
		return
	}
	if existing, err := q.media.FindByHash(jobCtx, hash); err == nil && existing != nil && existing.ID != 0 && !existing.DeletedAt.Valid {
		os.Remove(tmpPath)
		q.fail(job, fmt.Errorf("duplicate file"), "File already exists")
		return
	} else if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		os.Remove(tmpPath)
		q.fail(job, err, "Failed to check for duplicates")
		return
	}

	// Коммит: чужой файл под тем же именем (коллизия санитизированных
	// названий, сирота после ручного удаления) — не перезапись, а
	// суффикс. Путь записи — итоговый, не запланированный. Остаточное
	// окно между uniquePath и Link закрываем ретраем: коррупции быть
	// не может (Link атомарен), максимум — следующий суффикс.
	finalPath := dstPath
	committed := false
	for attempt := 0; attempt < 3 && !committed; attempt++ {
		finalPath = uniquePath(dstPath)
		if err := commitFile(tmpPath, finalPath); err != nil {
			if errors.Is(err, errExtractFileExists) {
				continue
			}
			os.Remove(tmpPath)
			q.fail(job, err, "Failed to save file")
			return
		}
		committed = true
		q.mu.Lock()
		job.outPath = finalPath
		q.mu.Unlock()
	}
	if !committed {
		os.Remove(tmpPath)
		q.fail(job, fmt.Errorf("%w: %s", errExtractFileExists, dstPath), "File already exists")
		return
	}

	info, _ := os.Stat(finalPath)
	fileSize := int64(0)
	if info != nil {
		fileSize = info.Size()
	}

	media := &models.Media{
		Title:         source.Title,
		Filename:      filepath.Base(finalPath),
		Year:          source.Year,
		Type:          models.MediaTypeAudio,
		Artists:       source.Artists,
		Album:         source.Album,
		Genre:         source.Genre,
		FilePath:      finalPath,
		FileSize:      fileSize,
		FileHash:      hash,
		SourceMediaID: &sourceID,
	}
	if media.Title == "" {
		media.Title = base
	}
	if err := q.media.Create(jobCtx, media); err != nil {
		os.Remove(finalPath)
		q.fail(job, err, "Failed to save media record")
		return
	}
	q.mu.Lock()
	job.MediaID = media.ID
	cancelled := job.Status == extractJobCancelled
	q.mu.Unlock()
	if cancelled {
		q.cleanupJob(finalPath, media.ID)
		return
	}

	// Длительность — из извлечённого файла (точная); остальные поля уже
	// скопированы с видео-источника и пустым не затираются.
	if fileMeta := q.extract.ExtractFromFileContext(jobCtx, finalPath); fileMeta != nil {
		if fileMeta.Duration > 0 {
			media.Duration = fileMeta.Duration
			if err := q.media.Update(jobCtx, media); err != nil {
				q.fail(job, err, "Failed to update media metadata")
				return
			}
		}
	}
	if cancelled := q.markCancelled(job); cancelled {
		q.cleanupJob(finalPath, media.ID)
		return
	}

	// Обложка из встроенного арта — как у обычных аудиозагрузок.
	if coverPath := q.thumbSvc.ExtractCoverContext(jobCtx, media.ID, finalPath); coverPath != "" {
		media.CoverURL = fmt.Sprintf("/api/media/%d/cover", media.ID)
		if err := q.media.Update(jobCtx, media); err != nil {
			q.fail(job, err, "Failed to update media cover")
			return
		}
	}

	q.mu.Lock()
	if job.Status == extractJobCancelled {
		q.mu.Unlock()
		q.cleanupJob(finalPath, media.ID)
		return
	}
	job.Status = ExtractJobDone
	job.Error = ""
	q.mu.Unlock()
	q.saveStatus(job)
}

// markCancelled проверяет отмену под локом (для проверок между этапами).
func (q *ExtractService) markCancelled(job *ExtractJob) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	return job.Status == extractJobCancelled
}

// ffmpegArgs собирает аргументы извлечения (чистая функция —
// тестируется без бинарника, в отличие от runFFmpeg).
func ffmpegArgs(src, dst string, target extractTarget) []string {
	args := []string{"-i", src, "-vn", "-n", "-f", target.format}
	// Только первая аудиодорожка: без -map copy тащил бы все дорожки
	// (комментарии, дубляж), а сборка .m4a из AAC+DTS падала бы.
	args = append(args, "-map", "0:a:0")
	if target.encodeFLAC {
		args = append(args, "-c:a", "flac")
	} else {
		args = append(args, "-c:a", "copy")
	}
	return append(args, dst)
}

// probeAudio — probeAudioCodec с точкой подмены для тестов.
func (q *ExtractService) probeAudio(ctx context.Context, path string) (string, float64, error) {
	if q.probeFn != nil {
		return q.probeFn(ctx, path)
	}
	return probeAudioCodec(ctx, path)
}

// runFFmpegForJob — runFFmpeg с точкой подмены для тестов.
func (q *ExtractService) runFFmpegForJob(ctx context.Context, src, dst string, target extractTarget, durationSecs float64) error {
	if q.runFFmpegFn != nil {
		return q.runFFmpegFn(ctx, src, dst, target, durationSecs)
	}
	return q.runFFmpeg(ctx, src, dst, target, durationSecs)
}

// runFFmpeg извлекает аудиодорожку: stream copy (качество 1:1) либо
// FLAC-encode для несовместимых кодеков. Таймаут масштабируется от
// длительности, но упёрт в потолок: зависший ffmpeg не должен держать
// воркер дольше часа. Контекст — per-job: отмена убивает процесс.
// `-n` вместо `-y`: перезапись — только через commitFile после проверок.
func (q *ExtractService) runFFmpeg(ctx context.Context, src, dst string, target extractTarget, durationSecs float64) error {
	timeout := 10 * time.Minute
	if scaled := time.Duration(durationSecs*3)*time.Second + 2*time.Minute; scaled > timeout {
		timeout = scaled
	}
	if timeout > maxExtractTimeout {
		timeout = maxExtractTimeout
	}
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	cmd := exec.CommandContext(cmdCtx, "ffmpeg", ffmpegArgs(src, dst, target)...)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %s", err, stderr.String())
	}
	return nil
}

// commitFile атомарно вводит готовый файл в библиотеку: частичный
// результат в сканируемой директории не светится (сканер иначе
// подхватил бы недописанное). Через жёсткую ссылку: link(2) падает
// с EEXIST, если dst уже занят — в отличие от пары Stat→Rename здесь
// нет окна гонки. Упавшую ссылку чистит вызывающий (tmp остаётся его).
func commitFile(tmpPath, dstPath string) error {
	if err := os.Link(tmpPath, dstPath); err != nil {
		if os.IsExist(err) {
			return fmt.Errorf("%w: %s", errExtractFileExists, dstPath)
		}
		return fmt.Errorf("commit file: %w", err)
	}
	// Тот же inode под двумя именами: tmp-имя больше не нужно.
	if err := os.Remove(tmpPath); err != nil {
		log.Printf("extract queue: remove tmp link %s: %v", tmpPath, err)
	}
	return nil
}

// uniquePath подбирает свободное имя: dst, затем `base (2).ext`…
// Нужно при коллизии санитизированных названий разных видео и при
// повторе после ручного удаления записи (файл-сирота цел, связки нет —
// это не дубль по контенту, а новое извлечение).
func uniquePath(dstPath string) string {
	if _, err := os.Stat(dstPath); os.IsNotExist(err) {
		return dstPath
	} else if err != nil {
		return dstPath
	}
	ext := filepath.Ext(dstPath)
	base := strings.TrimSuffix(dstPath, ext)
	for i := 2; i < 100; i++ {
		candidate := fmt.Sprintf("%s (%d)%s", base, i, ext)
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
	}
	return dstPath
}

// maxExtractFilename — потолок длины имени файла в байтах: запас под
// суффиксы uniquePath и длинные названия (лимит ФС — 255).
const maxExtractFilename = 150

// truncateFilename ужимает имя до лимита, сохраняя расширение и
// границу UTF-8 (набор по рунам с байтовым бюджетом).
func truncateFilename(filename string) string {
	if len(filename) <= maxExtractFilename {
		return filename
	}
	ext := filepath.Ext(filename)
	base := strings.TrimSuffix(filename, ext)
	room := maxExtractFilename - len(ext)
	if room <= 0 {
		return filename[:maxExtractFilename]
	}
	var b strings.Builder
	used := 0
	for _, r := range base {
		w := utf8.RuneLen(r)
		if used+w > room {
			break
		}
		b.WriteRune(r)
		used += w
	}
	if b.Len() == 0 {
		return filename[:maxExtractFilename]
	}
	return b.String() + ext
}

// probeAudioCodec возвращает кодек первой аудиодорожки ("", если нет)
// и длительность в секундах (0 при ошибке — только для таймаута).
func probeAudioCodec(ctx context.Context, filePath string) (string, float64, error) {
	probeCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	data, err := ffprobe.ProbeURL(probeCtx, filePath)
	if err != nil {
		return "", 0, err
	}
	duration := data.Format.Duration().Seconds()
	for _, s := range data.Streams {
		if s.CodecType == "audio" {
			return s.CodecName, duration, nil
		}
	}
	return "", duration, nil
}

func (q *ExtractService) fail(job *ExtractJob, err error, errMsg string) {
	q.mu.Lock()
	if job.Status == extractJobCancelled {
		q.mu.Unlock()
		log.Printf("extract queue: job %d already cancelled, ignoring failure: %v", job.ID, err)
		return
	}
	// Остановка очереди (SIGTERM при рестарте): терминальный error не
	// пишем, иначе управляемый рестарт терял бы задание вопреки контракту
	// recovery (поднимаются только queued/processing). Возвращаем в queued —
	// следующий старт подхватит задание как после краха.
	if q.ctx.Err() != nil {
		job.Status = ExtractJobQueued
		job.Error = ""
		q.mu.Unlock()
		q.saveStatus(job)
		log.Printf("extract queue: job %d requeued on shutdown", job.ID)
		return
	}
	job.Status = ExtractJobError
	job.Error = errMsg
	mediaID := job.MediaID
	// Поздние ошибки (метаданные/обложка) тоже уносят файл: чистим по
	// outPath, а не по пустому пути.
	outPath := job.outPath
	q.mu.Unlock()
	q.saveStatus(job)

	if mediaID != 0 || outPath != "" {
		q.cleanupJob(outPath, mediaID)
	}
	log.Printf("extract queue: job %d failed: %v", job.ID, err)
}

// cleanupJob удаляет файл, запись Media (purge, а не корзина — файл уже
// стёрт, восстанавливать нечего) и превью/обложки. Идемпотентна.
func (q *ExtractService) cleanupJob(filePath string, mediaID uint) {
	if filePath != "" {
		if err := os.Remove(filePath); err != nil && !os.IsNotExist(err) {
			log.Printf("extract queue: remove file %s: %v", filePath, err)
		}
	}
	if mediaID != 0 {
		if err := q.media.PurgeMedia(context.Background(), mediaID); err != nil {
			log.Printf("extract queue: delete media %d: %v", mediaID, err)
		}
		q.thumbSvc.RemoveCovers(mediaID)
		if err := os.Remove(q.thumbSvc.GetPath(mediaID)); err != nil && !os.IsNotExist(err) {
			log.Printf("extract queue: remove thumb %d: %v", mediaID, err)
		}
	}
}

func (q *ExtractService) sweepLoop() {
	defer q.wg.Done()
	ticker := time.NewTicker(extractSweepInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			q.sweep()
		case <-q.ctx.Done():
			return
		}
	}
}

func (q *ExtractService) sweep() {
	type agedJob struct {
		id        uint
		createdAt time.Time
	}

	var evicted []uint
	func() {
		q.mu.Lock()
		defer q.mu.Unlock()

		now := time.Now()
		for id, job := range q.jobs {
			if job.Status == ExtractJobQueued || job.Status == ExtractJobProcessing {
				continue
			}
			if now.Sub(job.createdAt) > extractJobTTL {
				delete(q.jobs, id)
				evicted = append(evicted, id)
			}
		}

		if len(q.jobs) <= maxKeptExtractJobs {
			return
		}
		var terminal []agedJob
		for id, job := range q.jobs {
			if job.Status != ExtractJobQueued && job.Status != ExtractJobProcessing {
				terminal = append(terminal, agedJob{id: id, createdAt: job.createdAt})
			}
		}
		sort.Slice(terminal, func(i, j int) bool {
			return terminal[i].createdAt.Before(terminal[j].createdAt)
		})
		overflow := len(q.jobs) - maxKeptExtractJobs
		for i := 0; i < overflow && i < len(terminal); i++ {
			delete(q.jobs, terminal[i].id)
			evicted = append(evicted, terminal[i].id)
		}
	}()
	for _, id := range evicted {
		if err := q.tasks.Delete(context.Background(), id); err != nil {
			log.Printf("extract queue: delete swept job %d: %v", id, err)
		}
	}
}
