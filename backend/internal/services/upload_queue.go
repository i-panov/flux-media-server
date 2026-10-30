package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"sort"
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
	// UploadJobDuplicate — картинка похожа на уже существующий мем;
	// запись и файл новой загрузки удалены.
	UploadJobDuplicate = "duplicate"
	// uploadJobCancelled — внутренний статус отменённого задания. Наружу
	// не возвращается: задание удаляется из очереди при отмене.
	uploadJobCancelled = "cancelled"
)

// Дефолтные параметры очереди загрузок.
const (
	DefaultUploadQueueLimit   = 50
	DefaultUploadQueueWorkers = 2
)

// uploadJobTTL — сколько терминальное задание (done/error) хранится в
// статусах для опроса GET /uploads/:id, прежде чем sweep его удалит.
// Клиент должен успеть получить статус; час — с большим запасом.
const uploadJobTTL = time.Hour

// maxKeptJobs — жёсткий потолок числа хранимых заданий: даже свежие
// терминальные не должны копиться бесконечно при интенсивных загрузках.
const maxKeptJobs = 1000

// uploadSweepInterval — периодичность фоновой очистки терминальных заданий.
const uploadSweepInterval = time.Minute

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
	// Force — пропустить проверку похожих картинок (пользователь
	// подтвердил, что это не дубль). Точный хэш всё равно проверяется.
	Force bool
}

// UploadJob — задание фоновой обработки загрузки. Все поля доступны только
// под mutex'ом очереди (воркер и хендлеры разделяют объект).
// ID — из БД (upload_tasks.id, стабилен между рестартами).
type UploadJob struct {
	ID        uint64
	Status    string
	Error     string
	MediaID   uint
	filePath  string
	filename  string
	mediaType models.MediaType
	force     bool
	// fileHash — sha256 файла, заполняется после хэширования и
	// персистится в строку (дедуп параллельных заливок одного контента).
	fileHash string
	// Заполняются при статусе duplicate: id и название похожего мема.
	duplicateMediaID uint
	duplicateTitle   string
	createdAt        time.Time
}

// UploadJobStatus — снимок статуса для API без доступа к внутренним полям.
type UploadJobStatus struct {
	Status           string
	Error            string
	MediaID          uint
	DuplicateMediaID uint
	DuplicateTitle   string
}

// UploadQueue — очередь фоновой обработки загрузок с персистентными
// строками (upload_tasks). Файл сохраняется синхронно в хендлере, а
// хэш/ffprobe/ffmpeg выполняются воркерами: запрос POST не висит
// по ~30 секунд на превью.
//
// Очередь — буферизованный канал размера limit + мапа заданий для
// GET/DELETE по ID. Stop() отменяет контекст (прерывая ffprobe/ffmpeg/
// хэширование через CommandContext/contextReader) и ждёт воркеров.
// Незавершённые строки переживают рестарт и перевыставляются в очередь
// при старте (см. recoverInterrupted).
type UploadQueue struct {
	mu sync.Mutex
	// phashMu сериализует проверку похожести и решение duplicate:
	// иначе два воркера видят друг друга и удаляют обе загрузки.
	phashMu sync.Mutex
	// fileHashMu сериализует позднюю проверку-и-создание (FindByHash по
	// Media → Create → фиксация MediaID): иначе два воркера, прошедшие
	// раннюю проверку, видят пустой результат и плодят дубли. Зеркало
	// pHash-пути: первый создаёт, второй видит запись и уходит в тот же
	// failDuplicateUpload. Ранняя проверка остаётся fast-path оптимизацией.
	fileHashMu sync.Mutex
	jobs       map[uint64]*UploadJob
	queue      chan *UploadJob
	limit      int
	// enqueueMu сериализует постановки: без него параллельные Enqueue
	// одного файла одновременно проходят проверку дедупа и плодят
	// дубли (check-then-act на карте + БД).
	enqueueMu sync.Mutex
	ctx       context.Context
	cancel    context.CancelFunc
	wg        sync.WaitGroup
	media     repository.MediaRepository
	tasks     repository.UploadTaskRepository
	thumbSvc  *ThumbnailService
	extract   *MetadataExtractor
}

// NewUploadQueue создаёт очередь и запускает workers воркеров. workers<0
// или limit<=0 подменяются дефолтными значениями; workers=0 — валидное
// значение «без воркеров» (используется в тестах для детерминированной
// проверки queued-состояния и переполнения очереди).
func NewUploadQueue(
	ctx context.Context,
	mediaRepo repository.MediaRepository,
	tasks repository.UploadTaskRepository,
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
		tasks:    tasks,
		thumbSvc: thumbSvc,
		extract:  NewMetadataExtractor(),
	}
	for i := 0; i < workers; i++ {
		q.wg.Add(1)
		go q.worker()
	}
	// Фоновая очистка терминальных заданий: без неё карта jobs росла бы
	// монотонно — Cancel чистит только отменённые, done/error копятся.
	q.wg.Add(1)
	go q.sweepLoop()
	q.recoverInterrupted()
	return q
}

// recoverInterrupted поднимает незавершённые строки из БД (следствие
// рестарта посреди обработки): сбрасывает processing в queued,
// пересоздаёт in-memory записи. ID раздаёт БД, переиспользования нет.
// Дедуп по файлу: два unfinished на один путь — след двойной постановки
// до краха, оставляем старейший. Отправка в канал — отдельной горутиной
// с блокировкой: unfinished может быть больше буфера, а конструктор
// блокироваться не должен.
func (q *UploadQueue) recoverInterrupted() {
	if q.tasks == nil {
		return
	}
	unfinished, err := q.tasks.FindUnfinished(context.Background(), UploadJobQueued, UploadJobProcessing)
	if err != nil {
		log.Printf("upload queue: load unfinished jobs: %v", err)
		return
	}
	seen := make(map[string]bool, len(unfinished))
	var ids []uint64
	for _, row := range unfinished {
		if seen[row.FilePath] {
			if err := q.tasks.Delete(context.Background(), row.ID); err != nil {
				log.Printf("upload queue: delete duplicate job %d: %v", row.ID, err)
			}
			continue
		}
		seen[row.FilePath] = true
		if row.Status == UploadJobProcessing {
			if err := q.tasks.SetStatus(context.Background(), row.ID, UploadJobQueued, "", row.MediaID); err != nil {
				log.Printf("upload queue: reset job %d: %v", row.ID, err)
				continue
			}
		}
		q.mu.Lock()
		q.jobs[row.ID] = &UploadJob{
			ID:               row.ID,
			Status:           UploadJobQueued,
			filePath:         row.FilePath,
			filename:         row.Filename,
			mediaType:        row.MediaType,
			force:            row.Force,
			fileHash:         row.FileHash,
			MediaID:          row.MediaID,
			duplicateMediaID: row.DuplicateMediaID,
			duplicateTitle:   row.DuplicateTitle,
			createdAt:        row.CreatedAt,
		}
		q.mu.Unlock()
		ids = append(ids, row.ID)
	}
	if len(ids) == 0 {
		return
	}
	log.Printf("upload queue: recovered %d interrupted job(s)", len(ids))
	q.wg.Add(1)
	go q.recoverQueue(ids)
}

func (q *UploadQueue) recoverQueue(ids []uint64) {
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

// saveStatus пишет переход в БД best-effort: недоступная БД ломает
// и остальной сервер, поэтому воркер продолжает in-memory.
func (q *UploadQueue) saveStatus(job *UploadJob) {
	if q.tasks == nil {
		return
	}
	q.mu.Lock()
	id, status, errMsg, mediaID := job.ID, job.Status, job.Error, job.MediaID
	q.mu.Unlock()
	if err := q.tasks.SetStatus(context.Background(), id, status, errMsg, mediaID); err != nil {
		log.Printf("upload queue: save task %d: %v", id, err)
	}
}

// saveFileHash фиксирует хэш файла в строке best-effort.
func (q *UploadQueue) saveFileHash(job *UploadJob, hash string) {
	if q.tasks == nil {
		return
	}
	q.mu.Lock()
	id := job.ID
	q.mu.Unlock()
	if err := q.tasks.SetFileHash(context.Background(), id, hash); err != nil {
		log.Printf("upload queue: save hash %d: %v", id, err)
	}
}

// checkParallelDuplicate — fast-path дедупа параллельных заливок одного
// контента под разными именами: после saveFileHash строка видна соседям,
// а записи Media ещё нет ни у кого. Нашёлся чужой активный джоб старше
// нас — завершаем текущее задание той же ошибкой дубликата, что поздний
// гейт по Media. Гарантии нет: детерминированность доводит только поздний
// гейт под fileHashMu (первый создаёт, второй уходит в failDuplicateUpload).
// Известное ограничение: упал старший позже — оба в error, лечится ретраем.
// true — задание завершено внутри, вызывающий возвращается.
func (q *UploadQueue) checkParallelDuplicate(job *UploadJob, hash string) bool {
	if hash == "" || q.tasks == nil {
		return false
	}
	jobID := job.ID
	active, err := q.tasks.FindActiveByHash(context.Background(), hash, UploadJobQueued, UploadJobProcessing)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false
		}
		q.fail(job, err, "Failed to check for duplicates")
		return true
	}
	if active == nil || active.ID == jobID || active.ID > jobID {
		return false
	}
	q.failDuplicateUpload(job)
	return true
}

// failDuplicateUpload завершает задание как точный дубль по хэшу: запись
// Media не создаётся, файл удаляется (см. fail/cleanupJobResources).
// Единая точка для ранней (по строкам) и поздней (по Media) проверок.
func (q *UploadQueue) failDuplicateUpload(job *UploadJob) {
	q.fail(job, errDuplicateUpload, "File already exists")
}

// Enqueue ставит задание в очередь и возвращает его ID. При переполнении
// возвращает ErrUploadQueueFull — файл на диске хендлер удаляет сам.
// Повторный POST того же файла, пока прошлый джоб летит
// (queued/processing, в т.ч. поднятый после рестарта), отдаёт ID
// существующего задания вместо нового.
func (q *UploadQueue) Enqueue(in UploadJobInput) (uint64, error) {
	// Сериализация всего check-then-act: карта + БД + вставка.
	q.enqueueMu.Lock()
	defer q.enqueueMu.Unlock()

	q.mu.Lock()
	for id, job := range q.jobs {
		if job.filePath == in.FilePath &&
			(job.Status == UploadJobQueued || job.Status == UploadJobProcessing) {
			q.mu.Unlock()
			return id, nil
		}
	}
	q.mu.Unlock()
	// Дыра после рестарта: поднятые задания уже в карте выше, но на
	// всякий случай проверяем и БД (один дешёвый запрос на постановку).
	if q.tasks != nil {
		if active, err := q.tasks.FindActiveByFilePath(context.Background(), in.FilePath, UploadJobQueued, UploadJobProcessing); err == nil && active != nil {
			return active.ID, nil
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("upload queue: find active job: %v", err)
		}
	}
	row := &models.UploadTask{
		FilePath:  in.FilePath,
		Filename:  in.Filename,
		MediaType: in.MediaType,
		Status:    UploadJobQueued,
		Force:     in.Force,
	}
	if q.tasks != nil {
		if err := q.tasks.Create(context.Background(), row); err != nil {
			return 0, err
		}
	} else {
		// Без репозитория (только старые тесты без БД) — ID из счётчика
		// невозможен без nextID; такой путь не используется.
		return 0, errors.New("upload queue: no task repository")
	}
	job := &UploadJob{
		ID:        row.ID,
		Status:    UploadJobQueued,
		filePath:  in.FilePath,
		filename:  in.Filename,
		mediaType: in.MediaType,
		force:     in.Force,
		createdAt: row.CreatedAt,
	}
	if job.createdAt.IsZero() {
		job.createdAt = time.Now()
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
			log.Printf("upload queue: delete overflowed job %d: %v", job.ID, err)
		}
		return 0, ErrUploadQueueFull
	}
}

// Get возвращает копию статуса задания. ok=false — задания нет.
// Сначала карта, затем БД: завершённые (но ещё не выметенные) строки
// переживают даже вытеснение из памяти и рестарт.
func (q *UploadQueue) Get(id uint64) (status, errMsg string, mediaID uint, ok bool) {
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
	if q.tasks == nil {
		return "", "", 0, false
	}
	row, err := q.tasks.Get(context.Background(), id)
	if err != nil {
		return "", "", 0, false
	}
	return row.Status, row.Error, row.MediaID, true
}

// Status возвращает полный снимок задания, включая данные о похожем меме
// для статуса duplicate. ok=false — задания нет.
// Сначала карта, затем БД: статус переживает вытеснение и рестарт.
func (q *UploadQueue) Status(id uint64) (UploadJobStatus, bool) {
	q.mu.Lock()
	job, found := q.jobs[id]
	var snap UploadJobStatus
	if found {
		snap = UploadJobStatus{
			Status:           job.Status,
			Error:            job.Error,
			MediaID:          job.MediaID,
			DuplicateMediaID: job.duplicateMediaID,
			DuplicateTitle:   job.duplicateTitle,
		}
	}
	q.mu.Unlock()
	if found {
		return snap, true
	}
	if q.tasks == nil {
		return UploadJobStatus{}, false
	}
	row, err := q.tasks.Get(context.Background(), id)
	if err != nil {
		return UploadJobStatus{}, false
	}
	return UploadJobStatus{
		Status:           row.Status,
		Error:            row.Error,
		MediaID:          row.MediaID,
		DuplicateMediaID: row.DuplicateMediaID,
		DuplicateTitle:   row.DuplicateTitle,
	}, true
}

// Cancel отменяет задание, если оно ещё не завершено: удаляет файл,
// запись Media (если создана), само задание и его строку в БД.
// Завершённое задание (done/duplicate) отменить нельзя — ErrUploadJobDone.
func (q *UploadQueue) Cancel(id uint64) error {
	q.mu.Lock()
	job, found := q.jobs[id]
	if !found {
		q.mu.Unlock()
		return ErrUploadJobNotFound
	}
	if job.Status == UploadJobDone || job.Status == UploadJobDuplicate {
		q.mu.Unlock()
		return ErrUploadJobDone
	}
	job.Status = uploadJobCancelled
	delete(q.jobs, id)
	// Снапшот ресурсов под локом: воркер может параллельно писать
	// job.MediaID в process — чтение полей job вне q.mu было бы гонкой.
	res := snapshotJobLocked(job)
	q.mu.Unlock()

	if q.tasks != nil {
		if err := q.tasks.Delete(context.Background(), id); err != nil {
			log.Printf("upload queue: delete cancelled job %d: %v", id, err)
		}
	}

	// Файловый I/O и удаление записи — вне q.mu, чтобы не блокировать
	// Get/Enqueue/воркеров на время os.Remove и DELETE из БД.
	q.cleanupJobResources(res)
	return nil
}

// jobResources — снапшот полей задания, нужных для очистки. Передаётся
// в cleanupJobResources вместо *UploadJob: указатель читался бы вне
// q.mu, конкурируя с записями воркера (data race).
type jobResources struct {
	jobID    uint64
	filePath string
	mediaID  uint
}

// snapshotJobLocked снимает снапшот ресурсов задания. Требует q.mu.
func snapshotJobLocked(job *UploadJob) jobResources {
	return jobResources{
		jobID:    job.ID,
		filePath: job.filePath,
		mediaID:  job.MediaID,
	}
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
	q.mu.Lock()
	if _, ok := q.jobs[job.ID]; !ok {
		// Задания нет в карте (Cancel удалил его, пока оно ждало
		// воркера): дроп без хэша/дедупа/создания. Чистить нечего —
		// Cancel уже всё убрал.
		q.mu.Unlock()
		return
	}
	if job.Status == uploadJobCancelled {
		// Зеркало earlyCancelled в extract: отмена между взятием из
		// канала и стартом — выходим до saveStatus и HashFileContext.
		q.mu.Unlock()
		return
	}
	job.Status = UploadJobProcessing
	job.Error = ""
	q.mu.Unlock()
	q.saveStatus(job)

	ctx := q.ctx

	hash, err := HashFileContext(ctx, job.filePath)
	if err != nil {
		q.fail(job, err, "Failed to hash file")
		return
	}
	q.mu.Lock()
	job.fileHash = hash
	q.mu.Unlock()
	q.saveFileHash(job, hash)

	// Ранний fast-path дедупа параллельных заливок одного контента под
	// разными именами: дедуп по file_path их не ловит, а поздний гейт
	// по Media ниже видит только готовые записи. Младший дубликат
	// выходит той же ошибкой, что поздний гейт; старший идёт дальше.
	// Полную детерминированность даёт только поздний гейт под fileHashMu.
	if q.checkParallelDuplicate(job, hash) {
		return
	}

	media, handled := q.checkAndCreateMedia(job, hash)
	if handled {
		return
	}
	q.continueWithMedia(job, media)
}

// checkAndCreateMedia — поздний гейт точных дубликатов под fileHashMu:
// проверка FindByHash по Media, Create и фиксация MediaID атомарны
// относительно друг друга (зеркало resolveDuplicate под phashMu). Даже
// при обоюдном проходе ранней проверки первый создаёт запись, а второй
// видит её и уходит в тот же failDuplicateUpload.
// Возвращает (media, false) — задание продолжается в continueWithMedia
// уже ВНЕ лока (там ffprobe/ffmpeg, держать мьютекс нельзя); (nil, true) —
// задание завершено внутри (дубль/восстановление/ошибка/отмена).
func (q *UploadQueue) checkAndCreateMedia(job *UploadJob, hash string) (*models.Media, bool) {
	ctx := q.ctx
	q.fileHashMu.Lock()
	defer q.fileHashMu.Unlock()

	q.mu.Lock()
	ownMediaID := job.MediaID
	q.mu.Unlock()

	existing, err := q.media.FindByHash(ctx, hash)
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		q.fail(job, err, "Failed to check for duplicates")
		return nil, true
	}
	if existing != nil && existing.ID != 0 {
		// Своя же недосозданная запись с прошлого прогона (крах между
		// Create и Done): не дубль, а незавершённая работа — подхватываем
		// её ниже вместо создания второй строки на тот же файл.
		// Возврат без handled: continueWithMedia идёт уже вне fileHashMu.
		if ownMediaID != 0 && existing.ID == ownMediaID {
			return existing, false
		}
		// Дубль по хэшу из корзины: не 409, а восстановление —
		// пользователь явно вернул тот же файл. Но только если файл
		// реально на месте: иначе зальёт заново, удалит хорошую копию
		// и воскресит указатель в никуда.
		if existing.DeletedAt.Valid {
			if st, statErr := os.Stat(existing.FilePath); statErr != nil || st.IsDir() {
				os.Remove(job.filePath)
				q.fail(job, errDuplicateUpload, "Original file is missing")
				return nil, true
			}
			os.Remove(job.filePath)
			if err := q.media.RestoreMedia(ctx, existing.ID); err != nil {
				q.fail(job, err, "Failed to restore media")
				return nil, true
			}
			// Джоба завершается успехом с восстановленной записью:
			// клиент увидит трек без повторной загрузки.
			q.succeedRestore(job, existing.ID)
			return nil, true
		}
		// Дубль по хэшу: запись не создаём, файл удаляем. Сообщение не
		// раскрывает путь к существующему файлу.
		q.failDuplicateUpload(job)
		return nil, true
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
		return nil, true
	}
	// MediaID фиксируем сразу после Create: и отмена, и fail обязаны
	// удалить созданную запись, даже если задание оборвётся на этапе
	// метаданных/превью. Строка в БД — сразу же, чтобы рестарт подхватил
	// связь и не счёл собственную запись чужым дублем.
	q.mu.Lock()
	job.MediaID = media.ID
	cancelled := job.Status == uploadJobCancelled
	res := snapshotJobLocked(job)
	q.mu.Unlock()
	q.saveStatus(job)
	if cancelled {
		q.cleanupJobResources(res)
		return nil, true
	}

	return media, false
}

// continueWithMedia доводит запись до done: ffprobe-метаданные,
// превью/обложка, pHash-дедуп. Общая для свежих и поднятых после краха
// заданий (у поднятых запись уже есть — своя же, см. process).
func (q *UploadQueue) continueWithMedia(job *UploadJob, media *models.Media) {
	ctx := q.ctx

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
		if fileMeta.Width > 0 {
			media.Width = fileMeta.Width
		}
		if fileMeta.Height > 0 {
			media.Height = fileMeta.Height
		}
		if fileMeta.Title != "" {
			media.Title = fileMeta.Title
		}
		if err := q.media.Update(ctx, media); err != nil {
			q.fail(job, err, "Failed to update media metadata")
			return
		}
	}
	if res, cancelled := q.cancelledSnapshot(job); cancelled {
		q.cleanupJobResources(res)
		return
	}

	// Превью (ffmpeg) для видео и картинок. В БД кладём относительный
	// URL — фронтенд строит полный адрес сам.
	thumbPath := q.thumbSvc.GenerateWithContext(ctx, media.ID, job.filePath)
	if thumbPath != "" {
		media.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", media.ID)
		if err := q.media.Update(ctx, media); err != nil {
			q.fail(job, err, "Failed to update media thumbnail")
			return
		}
	}
	if res, cancelled := q.cancelledSnapshot(job); cancelled {
		q.cleanupJobResources(res)
		return
	}

	// pHash считается с превью. Похожий мем не добавляем повторно:
	// точный дубль отсечён выше, force пропускает только эту проверку.
	if job.mediaType.IsImage() {
		phash := int64(0)
		if thumbPath != "" {
			hash, hashErr := ImagePHash(thumbPath)
			if hashErr != nil {
				// Битый файл не повод терять загрузку: запись остаётся,
				// просто без pHash.
				log.Printf("upload queue: image phash for job %d: %v", job.ID, hashErr)
			} else {
				phash = hash
			}
		}
		if phash != 0 {
			if err := q.media.SetPHash(ctx, media.ID, phash); err != nil {
				q.fail(job, err, "Failed to save image hash")
				return
			}
			duplicate, err := q.resolveDuplicate(ctx, job, phash)
			if err != nil {
				q.fail(job, err, "Failed to check for similar images")
				return
			}
			if duplicate {
				return
			}
		}
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
		res := snapshotJobLocked(job)
		q.mu.Unlock()
		q.cleanupJobResources(res)
		return
	}
	job.Status = UploadJobDone
	job.MediaID = media.ID
	job.Error = ""
	q.mu.Unlock()
	q.saveStatus(job)
}

// succeedRestore завершает джобу успехом на восстановленной из корзины
// записи: метаданные/обложки уже в БД и на диске, делать нечего.
func (q *UploadQueue) succeedRestore(job *UploadJob, mediaID uint) {
	q.mu.Lock()
	if job.Status == uploadJobCancelled {
		q.mu.Unlock()
		return
	}
	job.Status = UploadJobDone
	job.MediaID = mediaID
	job.Error = ""
	q.mu.Unlock()
	q.saveStatus(job)
}

// duplicate завершает задание статусом duplicate: новая запись, файл и
// превью удаляются, клиент получает id и название похожего мема.
func (q *UploadQueue) duplicate(job *UploadJob, similar *models.Media) {
	q.mu.Lock()
	if job.Status == uploadJobCancelled {
		q.mu.Unlock()
		return
	}
	job.Status = UploadJobDuplicate
	job.Error = ""
	job.duplicateMediaID = similar.ID
	job.duplicateTitle = similar.Title
	res := snapshotJobLocked(job)
	duplicateMediaID, duplicateTitle := job.duplicateMediaID, job.duplicateTitle
	jobID := job.ID
	q.mu.Unlock()

	if q.tasks != nil {
		if err := q.tasks.SetDuplicate(context.Background(), jobID, duplicateMediaID, duplicateTitle); err != nil {
			log.Printf("upload queue: save duplicate %d: %v", jobID, err)
		}
	}

	q.cleanupJobResources(res)
	log.Printf("upload queue: job %d duplicate of media %d (%s)", job.ID, similar.ID, similar.Title)
}

// resolveDuplicate под phashMu проверяет похожесть и сразу принимает
// решение. Два воркера с одинаковыми картинками не могут одновременно
// счесть друг друга дублями: первый удаляет свою запись до того, как
// второй начнёт поиск.
func (q *UploadQueue) resolveDuplicate(
	ctx context.Context,
	job *UploadJob,
	phash int64,
) (bool, error) {
	if job.force {
		return false, nil
	}
	q.phashMu.Lock()
	defer q.phashMu.Unlock()

	similar, err := FindSimilarImage(ctx, q.media, phash, job.MediaID)
	if err != nil {
		return false, err
	}
	if similar == nil {
		return false, nil
	}
	q.duplicate(job, similar)
	return true, nil
}

// cancelledSnapshot под одним локом проверяет отмену задания и снимает
// снапшот его ресурсов (для последующей очистки вне q.mu).
func (q *UploadQueue) cancelledSnapshot(job *UploadJob) (jobResources, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if job.Status != uploadJobCancelled {
		return jobResources{}, false
	}
	return snapshotJobLocked(job), true
}

// fail переводит задание в error и подчищает ресурсы. err логируется
// (безопасно — лог не уходит клиенту), errMsg отдаётся в API без утечки
// путей файловой системы. Отменённое задание не перезаписывается: cleanup
// уже выполнен Cancel'ом, статус остаётся cancelled.
func (q *UploadQueue) fail(job *UploadJob, err error, errMsg string) {
	q.mu.Lock()
	if job.Status == uploadJobCancelled {
		q.mu.Unlock()
		log.Printf("upload queue: job %d already cancelled, ignoring failure: %v", job.ID, err)
		return
	}
	// Остановка очереди (SIGTERM при рестарте): терминальный error не
	// пишем, иначе управляемый рестарт терял бы задание вопреки контракту
	// recovery (поднимаются только queued/processing). Возвращаем в queued —
	// следующий старт подхватит задание как после краха.
	if q.ctx.Err() != nil {
		job.Status = UploadJobQueued
		job.Error = ""
		q.mu.Unlock()
		q.saveStatus(job)
		log.Printf("upload queue: job %d requeued on shutdown", job.ID)
		return
	}
	job.Status = UploadJobError
	job.Error = errMsg
	res := snapshotJobLocked(job)
	q.mu.Unlock()
	q.saveStatus(job)

	// Файловый I/O и удаление записи — вне q.mu (см. Cancel).
	q.cleanupJobResources(res)
	log.Printf("upload queue: job %d failed: %v", job.ID, err)
}

// sweepLoop периодически удаляет терминальные задания старше TTL и
// следит за жёстким потолком размера карты.
func (q *UploadQueue) sweepLoop() {
	defer q.wg.Done()
	ticker := time.NewTicker(uploadSweepInterval)
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

// sweep удаляет терминальные (done/error/duplicate) задания старше
// uploadJobTTL. Активные (queued/processing) не трогаются независимо
// от возраста. Если после этого карта всё ещё больше maxKeptJobs,
// удаляются старейшие терминальные — карта не может расти бесконечно
// даже при интенсивных загрузках. Выметенные строки удаляются и из БД.
func (q *UploadQueue) sweep() {
	type agedJob struct {
		id        uint64
		createdAt time.Time
	}

	var evicted []uint64
	func() {
		q.mu.Lock()
		defer q.mu.Unlock()

		now := time.Now()
		for id, job := range q.jobs {
			if job.Status == UploadJobQueued || job.Status == UploadJobProcessing {
				continue
			}
			if now.Sub(job.createdAt) > uploadJobTTL {
				delete(q.jobs, id)
				evicted = append(evicted, id)
			}
		}

		if len(q.jobs) <= maxKeptJobs {
			return
		}
		var terminal []agedJob
		for id, job := range q.jobs {
			if job.Status != UploadJobQueued && job.Status != UploadJobProcessing {
				terminal = append(terminal, agedJob{id: id, createdAt: job.createdAt})
			}
		}
		sort.Slice(terminal, func(i, j int) bool {
			return terminal[i].createdAt.Before(terminal[j].createdAt)
		})
		overflow := len(q.jobs) - maxKeptJobs
		for i := 0; i < overflow && i < len(terminal); i++ {
			delete(q.jobs, terminal[i].id)
			evicted = append(evicted, terminal[i].id)
		}
	}()
	if q.tasks == nil {
		return
	}
	for _, id := range evicted {
		if err := q.tasks.Delete(context.Background(), id); err != nil {
			log.Printf("upload queue: delete swept job %d: %v", id, err)
		}
	}
}

// cleanupJobResources удаляет файл с диска, запись Media и превью/обложки.
// Вызывается БЕЗ q.mu: файловый I/O и DELETE из БД не должны блокировать
// Get/Enqueue/воркеров. Идемпотентна: повторные вызовы (воркер после
// Cancel) безопасны.
// Очистка обязана завершиться даже при остановленной очереди (Stop
// отменяет q.ctx), поэтому БД-операции идут с context.Background() —
// иначе после shutdown остались бы файлы-сироты и записи Media.
func (q *UploadQueue) cleanupJobResources(res jobResources) {
	if res.filePath != "" {
		if err := os.Remove(res.filePath); err != nil && !os.IsNotExist(err) {
			log.Printf("upload queue: remove file for job %d: %v", res.jobID, err)
		}
	}
	if res.mediaID != 0 {
		// Purge, а не Delete-корзина: файл уже стёрт выше, запись
		// недосозданная — восстанавливать нечего, а trashed-строка
		// с висячим путём только плодила бы мусор.
		if err := q.media.PurgeMedia(context.Background(), res.mediaID); err != nil {
			log.Printf("upload queue: delete media %d for job %d: %v", res.mediaID, res.jobID, err)
		}
		q.thumbSvc.RemoveCovers(res.mediaID)
		if err := os.Remove(q.thumbSvc.GetPath(res.mediaID)); err != nil && !os.IsNotExist(err) {
			log.Printf("upload queue: remove thumb for job %d: %v", res.jobID, err)
		}
	}
}
