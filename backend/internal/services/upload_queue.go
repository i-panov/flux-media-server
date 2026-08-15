package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"gorm.io/gorm"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

// Статусы задания загрузки (значения сериализуются в JSON API как есть).
const (
	UploadJobQueued     = "queued"
	UploadJobProcessing = "processing"
	UploadJobDone       = "done"
	UploadJobError      = "error"
	// uploadJobCancelled — внутренний статус отменённого задания. Наружу
	// не возвращается: задание удаляется из очереди при отмене.
	uploadJobCancelled = "cancelled"
)

// Дефолтные параметры очереди загрузок.
const (
	DefaultUploadQueueLimit   = 50
	DefaultUploadQueueWorkers = 2
)

// Ошибки очереди загрузок.
var (
	ErrUploadQueueFull   = errors.New("upload queue is full")
	ErrUploadJobNotFound = errors.New("upload job not found")
	ErrUploadJobDone     = errors.New("upload job already done")
)

// errDuplicateUpload — внутренний маркер дубликата по хэшу: не создаём
// запись Media, просто удаляем файл и ставим статус error.
var errDuplicateUpload = errors.New("duplicate file")

// UploadJobInput описывает задание: загруженный файл уже сохранён на диске.
type UploadJobInput struct {
	FilePath  string
	Filename  string
	MediaType models.MediaType
}

// UploadJob — задание фоновой обработки загрузки. Все поля доступны только
// под mutex'ом очереди (воркер и хендлеры разделяют объект).
type UploadJob struct {
	ID        uint64
	Status    string
	Error     string
	MediaID   uint
	filePath  string
	filename  string
	mediaType models.MediaType
	createdAt time.Time
}

// UploadQueue — in-memory очередь фоновой обработки загрузок. Файл
// сохраняется синхронно в хендлере, а хэш/ffprobe/ffmpeg выполняются
// воркерами: запрос POST не висит по ~30 секунд на превью.
//
// Очередь — буферизованный канал размера limit + мапа заданий для
// GET/DELETE по ID. Stop() отменяет контекст (прерывая ffprobe/ffmpeg/
// хэширование через CommandContext/contextReader) и ждёт воркеров.
type UploadQueue struct {
	mu       sync.Mutex
	jobs     map[uint64]*UploadJob
	queue    chan *UploadJob
	nextID   uint64
	limit    int
	ctx      context.Context
	cancel   context.CancelFunc
	wg       sync.WaitGroup
	media    repository.MediaRepository
	thumbSvc *ThumbnailService
	extract  *MetadataExtractor
}

// NewUploadQueue создаёт очередь и запускает workers воркеров. workers<0
// или limit<=0 подменяются дефолтными значениями; workers=0 — валидное
// значение «без воркеров» (используется в тестах для детерминированной
// проверки queued-состояния и переполнения очереди).
func NewUploadQueue(
	ctx context.Context,
	mediaRepo repository.MediaRepository,
	thumbSvc *ThumbnailService,
	workers, limit int,
) *UploadQueue {
	if workers < 0 {
		workers = DefaultUploadQueueWorkers
	}
	if limit <= 0 {
		limit = DefaultUploadQueueLimit
	}
	qctx, cancel := context.WithCancel(ctx)
	q := &UploadQueue{
		jobs:     make(map[uint64]*UploadJob),
		queue:    make(chan *UploadJob, limit),
		limit:    limit,
		ctx:      qctx,
		cancel:   cancel,
		media:    mediaRepo,
		thumbSvc: thumbSvc,
		extract:  NewMetadataExtractor(),
	}
	for i := 0; i < workers; i++ {
		q.wg.Add(1)
		go q.worker()
	}
	return q
}

// Enqueue ставит задание в очередь и возвращает его ID. При переполнении
// возвращает ErrUploadQueueFull — файл на диске хендлер удаляет сам.
func (q *UploadQueue) Enqueue(in UploadJobInput) (uint64, error) {
	q.mu.Lock()
	q.nextID++
	job := &UploadJob{
		ID:        q.nextID,
		Status:    UploadJobQueued,
		filePath:  in.FilePath,
		filename:  in.Filename,
		mediaType: in.MediaType,
		createdAt: time.Now(),
	}
	q.jobs[job.ID] = job
	q.mu.Unlock()

	select {
	case q.queue <- job:
		return job.ID, nil
	default:
		q.mu.Lock()
		delete(q.jobs, job.ID)
		q.mu.Unlock()
		return 0, ErrUploadQueueFull
	}
}

// Get возвращает копию статуса задания. ok=false — задания нет.
func (q *UploadQueue) Get(id uint64) (status, errMsg string, mediaID uint, ok bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	job, found := q.jobs[id]
	if !found {
		return "", "", 0, false
	}
	return job.Status, job.Error, job.MediaID, true
}

// Cancel отменяет задание, если оно ещё не завершено: удаляет файл,
// запись Media (если создана) и само задание. Done-задание отменить
// нельзя — ErrUploadJobDone.
func (q *UploadQueue) Cancel(id uint64) error {
	q.mu.Lock()
	job, found := q.jobs[id]
	if !found {
		q.mu.Unlock()
		return ErrUploadJobNotFound
	}
	if job.Status == UploadJobDone {
		q.mu.Unlock()
		return ErrUploadJobDone
	}
	job.Status = uploadJobCancelled
	delete(q.jobs, id)
	q.cleanupJob(job)
	q.mu.Unlock()
	return nil
}

// Stop останавливает воркеров: отменяет контекст (прерывая текущие
// операции) и ждёт завершения обработки текущих заданий.
func (q *UploadQueue) Stop() {
	q.cancel()
	q.wg.Wait()
}

// worker обрабатывает задания из канала до остановки очереди.
func (q *UploadQueue) worker() {
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

// safeProcess перехватывает панику воркера: паника не должна ронять
// процесс, а задание получает статус error.
func (q *UploadQueue) safeProcess(job *UploadJob) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("upload queue: worker panic for job %d: %v", job.ID, r)
			q.fail(job, fmt.Errorf("worker panic: %v", r), "Failed to process file")
		}
	}()
	q.process(job)
}

// process выполняет цепочку обработки: hash → дубль-проверка → запись
// Media → ffprobe-метаданные → превью/обложка → done. Ошибка любого
// этапа переводит задание в error, файл и запись удаляются.
func (q *UploadQueue) process(job *UploadJob) {
	q.setStatus(job, UploadJobProcessing, "")

	ctx := q.ctx

	hash, err := HashFileContext(ctx, job.filePath)
	if err != nil {
		q.fail(job, err, "Failed to hash file")
		return
	}

	existing, err := q.media.FindByHash(ctx, hash)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		q.fail(job, err, "Failed to check for duplicates")
		return
	}
	if existing != nil && existing.ID != 0 {
		// Дубль по хэшу: запись не создаём, файл удаляем. Сообщение не
		// раскрывает путь к существующему файлу.
		q.fail(job, errDuplicateUpload, "File already exists")
		return
	}

	title, year := metadata.ParseFilename(job.filename)
	info, _ := os.Stat(job.filePath)
	fileSize := int64(0)
	if info != nil {
		fileSize = info.Size()
	}

	media := &models.Media{
		Title:    title,
		Filename: job.filename,
		Year:     year,
		Type:     job.mediaType,
		FilePath: job.filePath,
		FileSize: fileSize,
		FileHash: hash,
	}

	if err := q.media.Create(ctx, media); err != nil {
		q.fail(job, err, "Failed to save media record")
		return
	}
	// MediaID фиксируем сразу после Create: и отмена, и fail обязаны
	// удалить созданную запись, даже если задание оборвётся на этапе
	// метаданных/превью.
	q.mu.Lock()
	job.MediaID = media.ID
	q.mu.Unlock()
	if q.isCancelled(job) {
		q.cleanupJob(job)
		return
	}

	// ffprobe-метаданные (длительность, теги). Сбой экстракции не роняет
	// задание: файл может не иметь тегов или быть обрезанным — запись
	// остаётся валидной.
	if fileMeta := q.extract.ExtractFromFileContext(ctx, job.filePath); fileMeta != nil {
		if fileMeta.Duration > 0 {
			media.Duration = fileMeta.Duration
		}
		if fileMeta.Artist != "" {
			media.Artists = []models.Artist{{Name: fileMeta.Artist}}
		}
		if fileMeta.Album != "" {
			media.Album = fileMeta.Album
		}
		if fileMeta.Genre != "" {
			media.Genre = fileMeta.Genre
		}
		if fileMeta.Title != "" {
			media.Title = fileMeta.Title
		}
		if err := q.media.Update(ctx, media); err != nil {
			q.fail(job, err, "Failed to update media metadata")
			return
		}
	}
	if q.isCancelled(job) {
		q.cleanupJob(job)
		return
	}

	// Превью (ffmpeg) для видео. В БД кладём относительный URL — фронтенд
	// строит полный адрес сам.
	if thumbPath := q.thumbSvc.GenerateWithContext(ctx, media.ID, job.filePath); thumbPath != "" {
		media.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", media.ID)
		if err := q.media.Update(ctx, media); err != nil {
			q.fail(job, err, "Failed to update media thumbnail")
			return
		}
	}
	if q.isCancelled(job) {
		q.cleanupJob(job)
		return
	}

	// Обложка из встроенного арта — только для аудио.
	if job.mediaType.IsAudio() {
		if coverPath := q.thumbSvc.ExtractCoverContext(ctx, media.ID, job.filePath); coverPath != "" {
			media.CoverURL = fmt.Sprintf("/api/media/%d/cover", media.ID)
			if err := q.media.Update(ctx, media); err != nil {
				q.fail(job, err, "Failed to update media cover")
				return
			}
		}
	}

	q.mu.Lock()
	if job.Status == uploadJobCancelled {
		q.mu.Unlock()
		q.cleanupJob(job)
		return
	}
	job.Status = UploadJobDone
	job.MediaID = media.ID
	job.Error = ""
	q.mu.Unlock()
}

// setStatus обновляет статус задания (игнорирует отменённые — cleanup уже
// выполнен или будет выполнен вызывающей стороной).
func (q *UploadQueue) setStatus(job *UploadJob, status, errMsg string) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if job.Status == uploadJobCancelled {
		return
	}
	job.Status = status
	job.Error = errMsg
}

// isCancelled проверяет, отменено ли задание.
func (q *UploadQueue) isCancelled(job *UploadJob) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	return job.Status == uploadJobCancelled
}

// fail переводит задание в error и подчищает ресурсы. err логируется
// (безопасно — лог не уходит клиенту), errMsg отдаётся в API без утечки
// путей файловой системы.
func (q *UploadQueue) fail(job *UploadJob, err error, errMsg string) {
	q.mu.Lock()
	job.Status = UploadJobError
	job.Error = errMsg
	q.cleanupJob(job)
	q.mu.Unlock()
	log.Printf("upload queue: job %d failed: %v", job.ID, err)
}

// cleanupJob удаляет файл с диска, запись Media и превью/обложки. Работает
// под q.mu и идемпотентна: повторные вызовы (воркер после Cancel) безопасны.
func (q *UploadQueue) cleanupJob(job *UploadJob) {
	if job.filePath != "" {
		if err := os.Remove(job.filePath); err != nil && !os.IsNotExist(err) {
			log.Printf("upload queue: remove file for job %d: %v", job.ID, err)
		}
	}
	if job.MediaID != 0 {
		if err := q.media.Delete(q.ctx, job.MediaID); err != nil {
			log.Printf("upload queue: delete media %d for job %d: %v", job.MediaID, job.ID, err)
		}
		q.thumbSvc.RemoveCovers(job.MediaID)
		if err := os.Remove(q.thumbSvc.GetPath(job.MediaID)); err != nil && !os.IsNotExist(err) {
			log.Printf("upload queue: remove thumb for job %d: %v", job.ID, err)
		}
	}
}
