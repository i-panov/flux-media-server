package services

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"gorm.io/gorm"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

// Статусы заданий нормализации (хранятся в БД — транскод идёт часами,
// рестарт сервера задание терять не должен).
const (
	TranscodeTaskQueued     = "queued"
	TranscodeTaskProcessing = "processing"
	TranscodeTaskDone       = "done"
	TranscodeTaskError      = "error"
	TranscodeTaskCancelled  = "cancelled"
)

const (
	// transcodePollInterval — страховка пропущенного wake: пропусков
	// быть не должно, но зависшая очередь хуже лишнего SELECT в минуту.
	transcodePollInterval = time.Minute
	// TranscodeTerminalTTL — сколько хранится история терминальных
	// заданий для админки. Экспортирована: cutoff нужен и списку
	// GET /api/admin/transcodes (handlers), и чистке sweepTerminal.
	TranscodeTerminalTTL = 7 * 24 * time.Hour
	// transcodeSweepInterval — периодичность чистки истории.
	transcodeSweepInterval = time.Hour
	// transcodeProgressDBInterval / Step — троттлинг записей прогресса:
	// тысячи апдейтов SQLite за фильм не нужны.
	transcodeProgressDBInterval = 2 * time.Second
	transcodeProgressDBStep     = 5
	// transcodeTimeoutCap — потолок одного файла (см. transcodeTimeout).
	transcodeTimeoutCap = 12 * time.Hour
	// transcodeSweepBatch — порция выборки истории за проход.
	transcodeSweepBatch = 1000
)

// Ошибки очереди транскода.
var (
	ErrTranscodeJobNotFound  = errors.New("transcode job not found")
	ErrTranscodeJobDone      = errors.New("transcode job already done")
	ErrTranscodeJobNotFailed = errors.New("transcode job is not failed")
	ErrInsufficientSpace     = errors.New("not enough disk space")
	// ErrTranscodeConflict — состояние задания изменилось между чтением
	// и записью (гонка Cancel/Retry/воркера): вызывающий повторяет запрос.
	ErrTranscodeConflict = errors.New("transcode job state changed, retry")
	// ErrDestinationExists — коммит упёрся в занятый путь (гонка имён):
	// вызывающий подбирает новое имя или ретраит.
	ErrDestinationExists = errors.New("destination already exists")
)

// TranscodeWorkerConfig — снимок нужных воркеру значений (plain-типы,
// не *config.Config: конструктор тестируется без конфига).
type TranscodeWorkerConfig struct {
	CRF             int
	Preset          string
	MaxHeight       int
	EstimateFactor  float64
	MaxAttempts     int
	LibraryVideoDir string
	OriginalsDir    string
	TempDir         string
	AutoCleanup     bool
}

// TranscodeJobStatus — плоский статус для API (та же форма, что у
// загрузок, плюс прогресс).
type TranscodeJobStatus struct {
	Status     string
	Error      string
	MediaID    uint
	Progress   int
	Speed      float64
	ETASeconds int64
}

// OriginalInfo — строка списка оригиналов для админки и авточистки.
type OriginalInfo struct {
	Name     string
	Size     int64
	Modified time.Time
	// Status — статус последнего задания: done/error/.../untracked
	// (файл положили вручную мимо загрузок)/orphaned (копии уже нет —
	// Media удалено или в корзине; такой оригинал не кандидат на чистку).
	Status  string
	MediaID uint
	Views   uint64
}

// TranscodeQueue — очередь нормализации видео: один воркер, задания
// в БД (переживают рестарт). Файл сохраняется синхронно в хендлере,
// probe/ffmpeg — в фоне.
type TranscodeQueue struct {
	mu          sync.Mutex
	running     map[uint64]context.CancelFunc
	wake        chan struct{}
	ctx         context.Context
	cancel      context.CancelFunc
	wg          sync.WaitGroup
	cfg         TranscodeWorkerConfig
	autoCleanup atomic.Bool
	tasks       repository.TranscodeTaskRepository
	media       repository.MediaRepository
	subs        repository.SubtitleRepository
	thumbSvc    *ThumbnailService
	runner      FFmpegRunner
	// freeBytes — шов для тестов (дефолт diskFreeBytes).
	freeBytes func(string) int64
}

// NewTranscodeQueue создаёт очередь и запускает воркера. Нулевые значения
// конфига подменяются дефолтами (тесты обходят config.Load).
func NewTranscodeQueue(
	ctx context.Context,
	cfg TranscodeWorkerConfig,
	tasks repository.TranscodeTaskRepository,
	media repository.MediaRepository,
	subs repository.SubtitleRepository,
	thumbSvc *ThumbnailService,
	runner FFmpegRunner,
) *TranscodeQueue {
	if cfg.CRF == 0 {
		cfg.CRF = 20
	}
	if cfg.Preset == "" {
		cfg.Preset = "fast"
	}
	if cfg.MaxHeight == 0 {
		cfg.MaxHeight = 1080
	}
	if cfg.EstimateFactor <= 0 {
		cfg.EstimateFactor = 1.5
	}
	if cfg.MaxAttempts < 1 {
		cfg.MaxAttempts = 3
	}
	qctx, cancel := context.WithCancel(ctx)
	q := &TranscodeQueue{
		running:   make(map[uint64]context.CancelFunc),
		wake:      make(chan struct{}, 1),
		ctx:       qctx,
		cancel:    cancel,
		cfg:       cfg,
		tasks:     tasks,
		media:     media,
		subs:      subs,
		thumbSvc:  thumbSvc,
		runner:    runner,
		freeBytes: diskFreeBytes,
	}
	q.autoCleanup.Store(cfg.AutoCleanup)
	q.wg.Add(1)
	go q.worker()
	q.wg.Add(1)
	go q.sweepLoop()
	return q
}

// AutoCleanup сообщает, включена ли авточистка оригиналов. Значение
// атомарное: админка переключает его на лету, без рестарта и без гонки
// с воркером, который читает флаг в ensureFreeSpace.
func (q *TranscodeQueue) AutoCleanup() bool {
	return q.autoCleanup.Load()
}

// SetAutoCleanup включает/выключает авточистку. При ошибке сохранения
// настройки вызывающий обязан вернуть прежнее значение.
func (q *TranscodeQueue) SetAutoCleanup(enabled bool) {
	q.autoCleanup.Store(enabled)
}

// Enqueue создаёт задание и будит воркера. Возвращает ID задания.
func (q *TranscodeQueue) Enqueue(sourcePath, filename string) (uint64, error) {
	task := &models.TranscodeTask{
		SourcePath: sourcePath,
		Filename:   filename,
		Status:     TranscodeTaskQueued,
	}
	if err := q.tasks.Create(context.Background(), task); err != nil {
		return 0, err
	}
	q.wakeWorker()
	return uint64(task.ID), nil
}

// Get возвращает статус задания для API. ok=false — задания нет.
func (q *TranscodeQueue) Get(id uint64) (TranscodeJobStatus, bool) {
	task, err := q.tasks.Get(context.Background(), uint(id))
	if err != nil {
		return TranscodeJobStatus{}, false
	}
	return TranscodeJobStatus{
		Status:     task.Status,
		Error:      task.ErrorMsg,
		MediaID:    task.MediaID,
		Progress:   task.Progress,
		Speed:      task.Speed,
		ETASeconds: estimateSeconds(task),
	}, true
}

// EstimateTranscodeETA — ETA для списков API из той же формулы, что у
// одиночного статуса Get: ненадёжные входные — 0.
func EstimateTranscodeETA(task *models.TranscodeTask) int64 {
	return estimateSeconds(task)
}

// estimateSeconds считает ETA из прогресса/скорости/длительности.
// Ненадёжные входные (нет длительности, нулевая скорость) — 0.
func estimateSeconds(task *models.TranscodeTask) int64 {
	if task == nil || task.Progress >= 100 || task.Speed <= 0 || task.DurationSecs <= 0 {
		return 0
	}
	return int64((100 - float64(task.Progress)) / 100 * task.DurationSecs / task.Speed)
}

// Cancel отменяет задание: queued — сразу (файл-исходник удаляется),
// processing — через контекст (воркер дочищает). Done отменять нельзя.
// Переход условный (только из активных/ошибочных): проигранная гонка
// с завершением воркера не воскрешает и не затирает его результат.
func (q *TranscodeQueue) Cancel(id uint64) error {
	for attempt := 0; attempt < 3; attempt++ {
		task, err := q.tasks.Get(context.Background(), uint(id))
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTranscodeJobNotFound
			}
			return err
		}
		switch task.Status {
		case TranscodeTaskDone:
			return ErrTranscodeJobDone
		case TranscodeTaskCancelled:
			return nil
		}
		task.Status = TranscodeTaskCancelled
		ok, err := q.tasks.UpdateIfStatus(context.Background(), task,
			TranscodeTaskQueued, TranscodeTaskProcessing, TranscodeTaskError)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}

		q.mu.Lock()
		cancel, running := q.running[uint64(task.ID)]
		if running {
			delete(q.running, uint64(task.ID))
		}
		q.mu.Unlock()

		if running {
			// Воркер увидит отмену и дочистит temp, исходник и результат.
			cancel()
			return nil
		}
		// Нас никто не опередит (переход наш), а воркера нет —
		// чистим исходник сами. Для error-статуса поведение прежнее:
		// файл уходит вместе с отказом от задания.
		if task.SourcePath != "" {
			if err := os.Remove(task.SourcePath); err != nil && !os.IsNotExist(err) {
				log.Printf("transcode: cancel remove source %d: %v", task.ID, err)
			}
		}
		return nil
	}
	return ErrTranscodeConflict
}

// CancelBySource отменяет активное задание для исходника (удаление
// оригинала из админки). Нет активного — nil (идемпотентно).
func (q *TranscodeQueue) CancelBySource(sourcePath string) error {
	task, err := q.tasks.FindLatestBySourcePath(context.Background(), sourcePath)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	if task.Status != TranscodeTaskQueued && task.Status != TranscodeTaskProcessing {
		return nil
	}
	return q.Cancel(uint64(task.ID))
}

// Retry возвращает failed-задание в очередь (счётчик попыток сбрасывается:
// ручной ретрай — осознанное решение админа, лимит не применяется).
// Переход условный: параллельный Cancel не затрется ретраем.
func (q *TranscodeQueue) Retry(id uint64) error {
	for attempt := 0; attempt < 3; attempt++ {
		task, err := q.tasks.Get(context.Background(), uint(id))
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTranscodeJobNotFound
			}
			return err
		}
		if task.Status == TranscodeTaskDone {
			return ErrTranscodeJobDone
		}
		if task.Status != TranscodeTaskError {
			return ErrTranscodeJobNotFailed
		}
		task.Status = TranscodeTaskQueued
		task.Attempts = 0
		task.Progress = 0
		task.Speed = 0
		task.ErrorMsg = ""
		ok, err := q.tasks.UpdateIfStatus(context.Background(), task, TranscodeTaskError)
		if err != nil {
			return err
		}
		if !ok {
			continue
		}
		q.wakeWorker()
		return nil
	}
	return ErrTranscodeConflict
}

// RequeueInterrupted возвращает зависшие processing-задания в queued
// и будит воркера: без wake подобранные задания ждали бы
// transcodePollInterval. Вызывается один раз при старте: только этот
// процесс пишет строки, значит processing — след упавшего воркера.
// Возвращает число строк.
func (q *TranscodeQueue) RequeueInterrupted(ctx context.Context) (int64, error) {
	n, err := q.tasks.ResetStuckProcessing(ctx, TranscodeTaskProcessing, TranscodeTaskQueued)
	if err != nil {
		return n, err
	}
	if n > 0 {
		q.wakeWorker()
	}
	return n, nil
}

// Stop останавливает воркера: отменяет контекст (прерывая текущий
// ffmpeg) и ждёт завершения.
func (q *TranscodeQueue) Stop() {
	q.cancel()
	q.wg.Wait()
}

func (q *TranscodeQueue) wakeWorker() {
	select {
	case q.wake <- struct{}{}:
	default:
	}
}

// worker разбирает очередь до остановки: drain-цикл после каждого
// сигнала, чтобы пачка Enqueue во время обработки не ждала тика.
func (q *TranscodeQueue) worker() {
	defer q.wg.Done()
	ticker := time.NewTicker(transcodePollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-q.wake:
		case <-ticker.C:
		case <-q.ctx.Done():
			return
		}
		for {
			if q.ctx.Err() != nil {
				return
			}
			task, ok := q.claimNext()
			if !ok {
				break
			}
			q.safeProcess(task)
		}
	}
}

// claimNext атомарно забирает старейшее queued-задание. Нет заданий —
// ErrRecordNotFound из репозитория, это штатно, не ошибка.
func (q *TranscodeQueue) claimNext() (*models.TranscodeTask, bool) {
	task, err := q.tasks.ClaimNextQueued(context.Background(), TranscodeTaskQueued, TranscodeTaskProcessing)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("transcode: claim next: %v", err)
		}
		return nil, false
	}
	return task, true
}

// safeProcess перехватывает панику воркера: задание уходит в error,
// процесс живёт.
func (q *TranscodeQueue) safeProcess(task *models.TranscodeTask) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("transcode: worker panic for task %d: %v", task.ID, r)
			q.fail(task, fmt.Errorf("worker panic: %v", r), "Failed to process file", true)
		}
	}()
	q.process(task)
}

// saveTask пишет строку, только если она всё ещё processing. false —
// прилетела отмена (или финал уже записан): обработка прерывается,
// чужая terminal-строка неприкосновенна. Все записи воркера идут
// только через этот метод.
func (q *TranscodeQueue) saveTask(task *models.TranscodeTask) bool {
	ok, err := q.tasks.UpdateIfStatus(context.Background(), task, TranscodeTaskProcessing)
	if err != nil {
		log.Printf("transcode: save task %d: %v", task.ID, err)
		return false
	}
	return ok
}

// process выполняет цепочку нормализации: hash → дедуп → probe →
// классификация → место → сабы в temp → convert/remux/move → проверка
// результата → запись Media → перенос сабов → превью → done.
// Запись Media создаётся только после успешной нормализации:
// оборванное задание не оставляет строк без файла.
func (q *TranscodeQueue) process(task *models.TranscodeTask) {
	jobCtx, cancel := context.WithCancel(q.ctx)
	q.mu.Lock()
	q.running[uint64(task.ID)] = cancel
	q.mu.Unlock()
	defer func() {
		q.mu.Lock()
		delete(q.running, uint64(task.ID))
		q.mu.Unlock()
		cancel()
	}()

	// Перечитываем: отмена могла прийти между claim и стартом.
	fresh, err := q.tasks.Get(context.Background(), task.ID)
	if err != nil || fresh.Status != TranscodeTaskProcessing {
		// Окно claim→старт: Cancel уже перевёл строку в cancelled,
		// а воркер до handleCancel не дошёл. Исходник чистим здесь,
		// иначе он останется в карантине с cancelled-строкой навсегда
		// (авточистка cancelled не берёт).
		if err == nil && fresh.Status == TranscodeTaskCancelled && fresh.SourcePath != "" {
			if rmErr := os.Remove(fresh.SourcePath); rmErr != nil && !os.IsNotExist(rmErr) {
				log.Printf("transcode: early-cancel remove source %d: %v", task.ID, rmErr)
			}
		}
		return
	}
	task = fresh

	// Временные файлы разделены по времени жизни: главный tmp чистят
	// сразу после execute, сайдкары — только после переноса. Иначе
	// чистка главного снесла бы ещё не перенесённые сайдкары.
	var mainTmp string
	var subTmps []string
	cleanupTempFiles := func() {
		for _, p := range append([]string{mainTmp}, subTmps...) {
			if p == "" {
				continue
			}
			if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
				log.Printf("transcode: remove temp %d (%s): %v", task.ID, p, err)
			}
		}
		mainTmp = ""
		subTmps = nil
	}
	cancelled := func() bool { return jobCtx.Err() != nil }
	// Причина отмены видна по строке: пользовательская (cancelled) —
	// чистим temp и исходник; остановка сервера — только temp, строка
	// остаётся processing и при старте подбирается RequeueInterrupted.
	// Чтение — фоновым контекстом: q.ctx уже мёртв при shutdown.
	handleCancel := func() {
		cleanupTempFiles()
		q.cancelCleanupSource(task)
	}
	// Backstop: чистка temp на любом выходе (включая fail-ветки и панику
	// до safeProcess) — идемпотентна, повторные вызовы безвредны.
	defer cleanupTempFiles()

	// 1. Исходник на месте? Админ мог удалить оригинал из карантина.
	info, err := os.Stat(task.SourcePath)
	if err != nil {
		q.failNoRetry(task, err, "Source file is missing")
		return
	}
	sourceSize := info.Size()

	// 2. Хэш исходника и дедуп.
	hash, err := HashFileContext(jobCtx, task.SourcePath)
	if cancelled() {
		handleCancel()
		return
	}
	if err != nil {
		q.fail(task, err, "Failed to hash file", true)
		return
	}
	task.SourceHash = hash
	if !q.saveTask(task) {
		// Проигранная гонка с Cancel: строка уже cancelled —
		// исходник чистит handleCancel, ретрай не нужен.
		handleCancel()
		return
	}
	if done, _ := q.checkDuplicate(jobCtx, task, hash); done {
		return
	}
	if cancelled() {
		handleCancel()
		return
	}

	// 3. Probe и классификация.
	probe, err := q.runner.Probe(jobCtx, task.SourcePath)
	if cancelled() {
		handleCancel()
		return
	}
	if err != nil {
		q.fail(task, err, "Failed to probe file", true)
		return
	}
	plan := ClassifyPlan(probe, q.cfg.MaxHeight)
	if !probe.HasVideo {
		q.failNoRetry(task, fmt.Errorf("no video stream"), "Not a video file")
		return
	}
	task.DurationSecs = probe.DurationSec
	if !q.saveTask(task) {
		handleCancel()
		return
	}

	// 4. Место под результат и temp (с авточисткой, если включена).
	resultEstimate := sourceSize
	tempNeed := int64(0)
	if plan.Kind == NormalizeFull || plan.Kind == NormalizeAudio {
		resultEstimate = int64(float64(sourceSize) * q.cfg.EstimateFactor)
		tempNeed = resultEstimate
	} else if plan.Kind == NormalizeRemux {
		tempNeed = sourceSize
	}
	protect := map[string]bool{task.SourcePath: true}
	if err := q.ensureFreeSpace(q.cfg.LibraryVideoDir, resultEstimate, protect); err != nil {
		q.fail(task, err, "Not enough disk space", true)
		return
	}
	if tempNeed > 0 {
		if err := q.ensureFreeSpace(q.cfg.TempDir, tempNeed, protect); err != nil {
			q.fail(task, err, "Not enough disk space", true)
			return
		}
	}
	if cancelled() {
		handleCancel()
		return
	}

	// 5. Субтитры в temp (индексы исходника ещё валидны). Ошибка —
	// только лог: идём дальше без сабов, как с метаданными в upload.
	subLangs := planSubLangs(plan.SubTracks)
	subTmps = q.extractSubtitlesToTmp(jobCtx, task, plan.SubTracks, subLangs)
	if cancelled() {
		handleCancel()
		return
	}

	// 6. Нормализация.
	resultPath, tmpPath, err := q.execute(jobCtx, task, plan)
	if resultPath != "" {
		// До Media.Create watcher не должен индексировать результат.
		releasePath := ReservePublishingPath(resultPath)
		defer releasePath()
	}
	mainTmp = tmpPath
	cleanupMainTmp := func() {
		if mainTmp != "" {
			if err := os.Remove(mainTmp); err != nil && !os.IsNotExist(err) {
				log.Printf("transcode: remove temp %d (%s): %v", task.ID, mainTmp, err)
			}
			mainTmp = ""
		}
	}
	cleanupMainTmp()
	if cancelled() {
		handleCancel()
		return
	}
	if err != nil {
		q.fail(task, err, "Failed to normalize file", true)
		return
	}

	// 7. Проверка результата для пересобранных файлов. Исходник
	// удаляется только для remux (обратим без потерь): audio/full —
	// lossy-шаги, оригинал остаётся в карантине. Direct уже перемещён,
	// валидация сделана probe исходника.
	if plan.Kind != NormalizeDirect {
		if ok := q.verifyResult(jobCtx, resultPath); !ok {
			// Результат уже в библиотеке, но Media ещё нет: иначе
			// watcher/scanner подберёт битый файл как отдельное видео.
			if rmErr := os.Remove(resultPath); rmErr != nil && !os.IsNotExist(rmErr) {
				log.Printf("transcode: remove invalid result %d: %v", task.ID, rmErr)
			}
			q.fail(task, fmt.Errorf("result verification failed"), "Failed to normalize file", true)
			return
		}
		if cancelled() {
			handleCancel()
			return
		}
	}

	// 8. Запись Media (полный объект до Create — ассоциаций нет,
	// затирать нечего).
	resultInfo, err := os.Stat(resultPath)
	if err != nil {
		q.fail(task, err, "Failed to stat result", true)
		return
	}
	resultHash, err := HashFileContext(jobCtx, resultPath)
	if cancelled() {
		handleCancel()
		return
	}
	if err != nil {
		q.fail(task, err, "Failed to hash result", true)
		return
	}
	resultQuick, err := quickHashFile(jobCtx, resultPath)
	if err != nil {
		q.fail(task, err, "Failed to hash result", true)
		return
	}
	title, year := metadata.ParseFilename(filepath.Base(resultPath))
	media := &models.Media{
		Title:      title,
		Filename:   filepath.Base(resultPath),
		Year:       year,
		Type:       models.MediaTypeVideo,
		FilePath:   resultPath,
		FileSize:   resultInfo.Size(),
		FileHash:   resultHash,
		SourceHash: hash,
		QuickHash:  resultQuick,
		Duration:   int(probe.DurationSec),
		Width:      probe.Width,
		Height:     probe.Height,
	}
	if err := q.media.Create(context.Background(), media); err != nil {
		q.fail(task, err, "Failed to save media record", true)
		return
	}
	task.MediaID = media.ID

	// 9. Перенос сайдкаров и регистрация. Ошибка — чистим переехавшее
	// и роняем задание (ретрай всё перегенерирует детерминированно).
	movedSubs, moveErr := q.moveSubtitles(subTmps, subLangs, resultPath, media.ID)
	if moveErr != nil {
		for _, p := range movedSubs {
			os.Remove(p)
		}
		// Direct уже перенёс исходник: результат — единственная копия.
		// Не удаляем его; фиксируем ошибку без ретрая.
		if _, statErr := os.Stat(task.SourcePath); statErr == nil {
			q.removeResult(media)
			q.fail(task, moveErr, "Failed to save subtitles", true)
		} else {
			q.fail(task, moveErr, "Failed to save subtitles", false)
		}
		return
	}
	subRows := make([]models.Subtitle, 0, len(movedSubs))
	for i, p := range movedSubs {
		subRows = append(subRows, models.Subtitle{Lang: subLangs[i], Path: p})
	}
	// Пустой ReplaceForMedia — лишняя транзакция и лишний шанс упасть
	// после того, как Direct уже забрал единственный исходник.
	if len(subRows) > 0 {
		if err := q.subs.ReplaceForMedia(context.Background(), media.ID, subRows); err != nil {
			for _, p := range movedSubs {
				os.Remove(p)
			}
			if _, statErr := os.Stat(task.SourcePath); statErr == nil {
				q.removeResult(media)
				q.fail(task, err, "Failed to save subtitles", true)
			} else {
				q.fail(task, err, "Failed to save subtitles", false)
			}
			return
		}
	}
	if cancelled() {
		// Не удаляем единственную копию, если Direct уже перенёс исходник.
		if _, statErr := os.Stat(task.SourcePath); statErr == nil {
			q.removeResult(media)
		}
		handleCancel()
		return
	}

	// 10. Превью. Генерация без превью — не ошибка (как в upload),
	// а вот сбой записи URL — да.
	if thumbPath := q.thumbSvc.GenerateWithContext(jobCtx, media.ID, resultPath); thumbPath != "" {
		media.ThumbnailURL = fmt.Sprintf("/api/media/%d/thumb", media.ID)
		if err := q.media.Update(context.Background(), media); err != nil {
			// Результат создан, но состояние не записалось. Если исходник
			// ещё на месте — ретрай возможен, чистим результат. Если исходник
			// уже перемещён/удалён (Direct/Remux), результат — единственная
			// копия: удалять его нельзя, ретрай всё равно упрётся в
			// отсутствующий SourcePath.
			sourceExists := false
			if _, statErr := os.Stat(task.SourcePath); statErr == nil {
				sourceExists = true
			}
			if sourceExists {
				q.removeResult(media)
			}
			q.fail(task, err, "Failed to update media thumbnail", sourceExists)
			return
		}
	}

	task.Status = TranscodeTaskDone
	task.Progress = 100
	task.Speed = 0
	task.ErrorMsg = ""
	if !q.saveTask(task) {
		// Гонку выиграла отмена: готовые файл и запись остаются (удалять
		// валидный результат из-за опоздавшей отмены хуже), а исходник
		// уходит по правилам отмены — handleCancel чистит temp и его.
		log.Printf("transcode: task %d finished after cancel, keeping result", task.ID)
		handleCancel()
		return
	}
	// Remux больше не нужен: результат успешно записан. Для Direct
	// исходник уже перенесён внутри execute.
	if plan.Kind == NormalizeRemux {
		if err := os.Remove(task.SourcePath); err != nil && !os.IsNotExist(err) {
			log.Printf("transcode: remove remux source %d: %v", task.ID, err)
		}
	}
}

// checkDuplicate проверяет повторную заливку по хэшу исходника и хэшу
// результата: живая запись — дубль, trashed с целым файлом —
// восстановление (перекодировать нечего), активное задание — дубль.
// Возвращает true, если задание терминально завершено внутри.
func (q *TranscodeQueue) checkDuplicate(ctx context.Context, task *models.TranscodeTask, hash string) (bool, string) {
	if hash == "" {
		return false, ""
	}
	if done, msg := q.checkHashMatch(ctx, task, hash, true); done {
		return true, msg
	}
	if done, msg := q.checkHashMatch(ctx, task, hash, false); done {
		return true, msg
	}
	if active, err := q.tasks.FindActiveBySourceHash(ctx, hash, TranscodeTaskQueued, TranscodeTaskProcessing); err == nil && active != nil && active.ID != task.ID {
		os.Remove(task.SourcePath)
		q.failNoRetry(task, fmt.Errorf("duplicate file"), "File is already being processed")
		return true, "duplicate"
	} else if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		q.fail(task, err, "Failed to check for duplicates", true)
		return true, "error"
	}
	return false, ""
}

// checkHashMatch сверяет хэш с Media: bySource — по SourceHash,
// иначе по FileHash.
func (q *TranscodeQueue) checkHashMatch(ctx context.Context, task *models.TranscodeTask, hash string, bySource bool) (bool, string) {
	var existing *models.Media
	var err error
	if bySource {
		existing, err = q.media.FindBySourceHash(ctx, hash)
	} else {
		existing, err = q.media.FindByHash(ctx, hash)
	}
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false, ""
		}
		q.fail(task, err, "Failed to check for duplicates", true)
		return true, "error"
	}
	if existing == nil || existing.ID == 0 {
		return false, ""
	}
	if existing.DeletedAt.Valid {
		// Восстанавливаем только если файл копии на месте: иначе
		// единственная копия — только что загруженный исходник,
		// удалять его нельзя — обрабатываем как новую загрузку.
		if st, statErr := os.Stat(existing.FilePath); statErr != nil || st.IsDir() {
			log.Printf("transcode: trashed copy %d missing, processing as new upload", existing.ID)
			return false, ""
		}
		if err := q.media.RestoreMedia(ctx, existing.ID); err != nil {
			q.fail(task, err, "Failed to restore media", true)
			return true, "error"
		}
		os.Remove(task.SourcePath)
		task.Status = TranscodeTaskDone
		task.Progress = 100
		task.MediaID = existing.ID
		task.ErrorMsg = ""
		if !q.saveTask(task) {
			return true, "restored"
		}
		return true, "restored"
	}
	os.Remove(task.SourcePath)
	q.failNoRetry(task, fmt.Errorf("duplicate file"), "File already exists")
	return true, "duplicate"
}

// execute выполняет план и возвращает путь результата в библиотеке
// плюс путь главного tmp ("" для direct). Исходник не удаляет:
// удаление — только после проверки результата.
func (q *TranscodeQueue) execute(jobCtx context.Context, task *models.TranscodeTask, plan NormalizePlan) (dst, tmp string, err error) {
	filename := truncateFilename(task.Filename)
	switch plan.Kind {
	case NormalizeDirect:
		dst := uniquePath(filepath.Join(q.cfg.LibraryVideoDir, filename))
		if err := commitExclusive(task.SourcePath, dst); err != nil {
			return "", "", err
		}
		return dst, "", nil
	case NormalizeRemux, NormalizeAudio, NormalizeFull:
		stem := strings.TrimSuffix(filename, filepath.Ext(filename))
		tmp = filepath.Join(q.cfg.TempDir, fmt.Sprintf("transcode-%d.mp4", task.ID))
		switch plan.Kind {
		case NormalizeRemux:
			if err := q.runner.RemuxCopy(jobCtx, task.SourcePath, tmp, plan); err != nil {
				return "", tmp, err
			}
		case NormalizeAudio:
			cb := q.progressCallback(task)
			if err := q.runner.FixAudio(jobCtx, task.SourcePath, tmp, plan, transcodeTimeoutCap, cb); err != nil {
				return "", tmp, err
			}
		default:
			cb := q.progressCallback(task)
			if err := q.runner.TranscodeVideo(jobCtx, task.SourcePath, tmp, plan, TranscodeOptions{
				CRF:        q.cfg.CRF,
				Preset:     q.cfg.Preset,
				MaxHeight:  q.cfg.MaxHeight,
				TimeoutCap: transcodeTimeoutCap,
			}, cb); err != nil {
				return "", tmp, err
			}
		}
		info, err := os.Stat(tmp)
		if err != nil || info.Size() == 0 {
			return "", tmp, fmt.Errorf("transcode produced empty result")
		}
		dst := uniquePath(filepath.Join(q.cfg.LibraryVideoDir, stem+".mp4"))
		if err := commitExclusive(tmp, dst); err != nil {
			return "", tmp, err
		}
		return dst, "", nil
	default:
		return "", "", fmt.Errorf("unknown normalize kind %q", plan.Kind)
	}
}

// verifyResult проверяет пересобранный файл probe: видеопоток обязан
// быть. Direct не проверяется (перемещённые байты, валидация уже
// сделана probe исходника).
func (q *TranscodeQueue) verifyResult(jobCtx context.Context, resultPath string) bool {
	probe, err := q.runner.Probe(jobCtx, resultPath)
	if err != nil {
		log.Printf("transcode: verify probe %s: %v", resultPath, err)
		return false
	}
	if !probe.HasVideo {
		log.Printf("transcode: verify %s has no video stream", resultPath)
		return false
	}
	return true
}

// progressCallback возвращает колбэк прогресса с троттлингом записей:
// чаще раза в 2 секунды или +5% в БД не пишем.
func (q *TranscodeQueue) progressCallback(task *models.TranscodeTask) func(ProgressUpdate) {
	lastWrite := time.Now().Add(-transcodeProgressDBInterval)
	lastPercent := -transcodeProgressDBStep
	return func(update ProgressUpdate) {
		percent := int(update.Percent)
		if percent < 0 {
			percent = 0
		}
		if percent > 100 {
			percent = 100
		}
		if time.Since(lastWrite) < transcodeProgressDBInterval && percent-lastPercent < transcodeProgressDBStep {
			return
		}
		lastWrite = time.Now()
		lastPercent = percent
		task.Progress = percent
		task.Speed = update.Speed
		q.saveTask(task)
	}
}

// planSubLangs считает финальные языки дорожек с дедупликацией
// (eng,eng → eng,eng2).
func planSubLangs(subs []SubTrack) []string {
	seen := make(map[string]int)
	langs := make([]string, 0, len(subs))
	for _, sub := range subs {
		base := sanitizeLang(sub.Lang)
		lang := base
		if n := seen[base]; n > 0 {
			lang = fmt.Sprintf("%s%d", base, n+1)
		}
		seen[base]++
		langs = append(langs, lang)
	}
	return langs
}

// extractSubtitlesToTmp извлекает текстовые дорожки по одной в temp.
// Имена детерминированы (task+lang): ретрай перезаписывает (-y).
// Возвращает пути созданных файлов; ошибка — только лог вызывающему.
func (q *TranscodeQueue) extractSubtitlesToTmp(ctx context.Context, task *models.TranscodeTask, subs []SubTrack, langs []string) []string {
	var created []string
	for i, sub := range subs {
		out := filepath.Join(q.cfg.TempDir, fmt.Sprintf("transcode-%d.%s.vtt", task.ID, langs[i]))
		if err := q.runner.ExtractSubtitles(ctx, task.SourcePath, sub, out); err != nil {
			log.Printf("transcode: subtitles for task %d: %v", task.ID, err)
			for _, p := range created {
				os.Remove(p)
			}
			return nil
		}
		created = append(created, out)
	}
	return created
}

// moveSubtitles переносит сайдкары к результату. Имя включает media ID
// (<stem>.<id>.<lang>.vtt): стемы видео неуникальны (film.mov после
// direct и film.mp4 после транскода делят stem), а ID — навсегда.
// С varние dst сначала сносится (ретрай после частичного переноса),
// затем exclusive-коммит. Возвращает финальные пути успешно перенесённых.
func (q *TranscodeQueue) moveSubtitles(created, langs []string, resultPath string, mediaID uint) ([]string, error) {
	dir := filepath.Dir(resultPath)
	stem := strings.TrimSuffix(filepath.Base(resultPath), filepath.Ext(resultPath))
	var moved []string
	for i, tmp := range created {
		dst := filepath.Join(dir, fmt.Sprintf("%s.%d.%s.vtt", stem, mediaID, langs[i]))
		os.Remove(dst)
		if err := commitExclusive(tmp, dst); err != nil {
			for _, p := range moved {
				os.Remove(p)
			}
			return nil, err
		}
		moved = append(moved, dst)
	}
	return moved, nil
}

// sanitizeLang приводит языковой тег к правилу ValidSubtitleLang:
// [a-z0-9-], сегменты непустые, длина 2..12. Иначе — "und".
// То же правило проверяет ServeSub — источник правды один.
func sanitizeLang(lang string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(lang) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' {
			b.WriteRune(r)
		}
	}
	if !ValidSubtitleLang(b.String()) {
		return "und"
	}
	return b.String()
}

// SubtitleLangPattern — единый шаблон языковых тегов сайдкаров:
// сегменты [a-z0-9]+ через дефис. Используют и sanitizeLang,
// и проверка ServeSub в хендлерах.
var SubtitleLangPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)

// ValidSubtitleLang — правило языковых тегов сайдкаров: шаблон выше
// плюс общая длина 2..12.
func ValidSubtitleLang(lang string) bool {
	if len(lang) < 2 || len(lang) > 12 {
		return false
	}
	return SubtitleLangPattern.MatchString(lang)
}

// removeResult сносит результат вместе с записью, сабами и превью:
// отмена после создания Media не должна оставлять сирот.
func (q *TranscodeQueue) removeResult(media *models.Media) {
	if subs, err := q.subs.ListByMedia(context.Background(), media.ID); err == nil {
		for _, sub := range subs {
			if err := os.Remove(sub.Path); err != nil && !os.IsNotExist(err) {
				log.Printf("transcode: remove sub %s: %v", sub.Path, err)
			}
		}
	}
	if err := q.subs.DeleteByMedia(context.Background(), media.ID); err != nil {
		log.Printf("transcode: delete subs %d: %v", media.ID, err)
	}
	if err := os.Remove(media.FilePath); err != nil && !os.IsNotExist(err) {
		log.Printf("transcode: remove result %s: %v", media.FilePath, err)
	}
	if err := q.media.PurgeMedia(context.Background(), media.ID); err != nil {
		log.Printf("transcode: purge media %d: %v", media.ID, err)
		// Файл уже удалён: оставлять живой ряд нельзя, иначе повторный
		// checkHashMatch примет его за дубликат и снесёт исходник.
		if delErr := q.media.Delete(context.Background(), media.ID); delErr != nil {
			log.Printf("transcode: soft-delete media %d after purge failure: %v", media.ID, delErr)
		}
	}
	q.thumbSvc.RemoveCovers(media.ID)
	if err := os.Remove(q.thumbSvc.GetPath(media.ID)); err != nil && !os.IsNotExist(err) {
		log.Printf("transcode: remove thumb %d: %v", media.ID, err)
	}
}

// fail переводит задание в error (с ретраем до лимита) или обратно
// в queued. Оригинал НЕ удаляется: он понадобится ретраю и админу.
// Запись — условная: проигранная гонка с Cancel не воскрешает строку.
func (q *TranscodeQueue) fail(task *models.TranscodeTask, err error, errMsg string, retryable bool) {
	task.Attempts++
	if retryable && task.Attempts < q.cfg.MaxAttempts {
		task.Status = TranscodeTaskQueued
		task.ErrorMsg = ""
		task.Progress = 0
		if !q.saveTask(task) {
			// Проигранная гонка с Cancel: temp приберёт defer
			// cleanupTempFiles, исходник — handleCancel ниже.
			q.cancelCleanupSource(task)
			return
		}
		q.wakeWorker()
		log.Printf("transcode: task %d failed (attempt %d), requeued: %v", task.ID, task.Attempts, err)
		return
	}
	task.Status = TranscodeTaskError
	task.ErrorMsg = errMsg
	if !q.saveTask(task) {
		q.cancelCleanupSource(task)
		return
	}
	log.Printf("transcode: task %d failed: %v", task.ID, err)
}

// cancelCleanupSource удаляет исходник, если строка отменена.
// Отдельно от handleCancel: у fail() нет доступа к списку temp,
// а temp покрывает отложенный cleanupTempFiles.
func (q *TranscodeQueue) cancelCleanupSource(task *models.TranscodeTask) {
	row, err := q.tasks.Get(context.Background(), task.ID)
	if err == nil && row.Status == TranscodeTaskCancelled && task.SourcePath != "" {
		if err := os.Remove(task.SourcePath); err != nil && !os.IsNotExist(err) {
			log.Printf("transcode: cancel remove source %d: %v", task.ID, err)
		}
	}
}

// failNoRetry — терминальная ошибка без траты попыток (детерминированные
// случаи: нет исходника, не видео, дубль).
func (q *TranscodeQueue) failNoRetry(task *models.TranscodeTask, err error, errMsg string) {
	task.Attempts = q.cfg.MaxAttempts
	q.fail(task, err, errMsg, false)
}

// EnsureSpaceForUpload проверяет место в карантине под входящий файл.
// Вызывается синхронно в хендлере до сохранения.
func (q *TranscodeQueue) EnsureSpaceForUpload(fileSize int64) error {
	return q.ensureFreeSpace(q.cfg.OriginalsDir, fileSize, nil)
}

// ensureFreeSpace гарантирует need свободных байт в dir: при нехватке
// и включённой авточистке удаляет готовые оригиналы по порядку
// (меньше просмотров → больше размер), иначе — ErrInsufficientSpace.
// protect — пути, которые трогать нельзя. Неизвестный остаток (-1,
// не-unix) — пропуск проверки, как в checkDiskSpace.
func (q *TranscodeQueue) ensureFreeSpace(dir string, need int64, protect map[string]bool) error {
	for {
		free := q.freeBytes(dir)
		if free < 0 || free >= need {
			return nil
		}
		if !q.AutoCleanup() {
			return ErrInsufficientSpace
		}
		victim, ok := q.nextEvictionVictim(protect)
		if !ok {
			return ErrInsufficientSpace
		}
		path := filepath.Join(q.cfg.OriginalsDir, victim.Name)
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			log.Printf("transcode: auto-cleanup remove %s: %v", path, err)
			return err
		}
		log.Printf("transcode: auto-cleanup removed %s (%d bytes, %d views)", victim.Name, victim.Size, victim.Views)
	}
}

// nextEvictionVictim возвращает первого кандидата на удаление: только
// оригиналы с готовой нормализованной копией (status done), сначала
// наименее смотримые, внутри — самые большие.
func (q *TranscodeQueue) nextEvictionVictim(protect map[string]bool) (OriginalInfo, bool) {
	originals, err := q.OriginalsStatus()
	if err != nil {
		log.Printf("transcode: auto-cleanup list originals: %v", err)
		return OriginalInfo{}, false
	}
	for _, info := range originals {
		if info.Status != TranscodeTaskDone {
			continue
		}
		if protect[filepath.Join(q.cfg.OriginalsDir, info.Name)] {
			continue
		}
		return info, true
	}
	return OriginalInfo{}, false
}

// OriginalsStatus возвращает файлы карантина со статусами заданий
// и просмотрами, отсортированные порядком чистки: просмотры по
// возрастанию, размер по убыванию, имя — для детерминированности.
// Копия удалена или в корзине (Media не находится живой строкой) —
// статус orphaned: такой оригинал не кандидат на авточистку, иначе
// можно удалить последнюю копию.
func (q *TranscodeQueue) OriginalsStatus() ([]OriginalInfo, error) {
	entries, err := os.ReadDir(q.cfg.OriginalsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	ctx := context.Background()
	infos := make([]OriginalInfo, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		full := filepath.Join(q.cfg.OriginalsDir, entry.Name())
		item := OriginalInfo{
			Name:     entry.Name(),
			Size:     info.Size(),
			Modified: info.ModTime(),
			Status:   "untracked",
		}
		if task, err := q.tasks.FindLatestBySourcePath(ctx, full); err == nil && task != nil {
			item.Status = task.Status
			item.MediaID = task.MediaID
			if task.Status == TranscodeTaskDone && task.MediaID != 0 {
				if media, err := q.media.FindByID(ctx, task.MediaID); err == nil && media != nil {
					// Живой строки мало: файл копии обязан существовать
					// (удалён вручную — сканер ещё не убрал строку).
					// Иначе авточистка снесла бы последнюю копию.
					if st, statErr := os.Stat(media.FilePath); statErr == nil && !st.IsDir() {
						item.Views = media.ViewCount
					} else {
						item.Status = "orphaned"
					}
				} else {
					// Копии нет (purged) или она в корзине: удалять
					// оригинал нельзя — помечаем отдельно.
					item.Status = "orphaned"
				}
			}
		} else if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("transcode: task lookup %s: %v", full, err)
		}
		infos = append(infos, item)
	}
	sort.Slice(infos, func(i, j int) bool {
		if infos[i].Views != infos[j].Views {
			return infos[i].Views < infos[j].Views
		}
		if infos[i].Size != infos[j].Size {
			return infos[i].Size > infos[j].Size
		}
		return infos[i].Name < infos[j].Name
	})
	return infos, nil
}

// commitExclusive переносит src в dst: hardlink внутри одной ФС
// (атомарно; занятый dst — ошибка, не перезапись), иначе копирование
// с O_EXCL. EEXIST означает гонку имён: вызывающий подбирает новое имя
// (uniquePath) или ретраит — молчаливой перезаписи нет никогда.
func commitExclusive(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0755); err != nil {
		return err
	}
	if err := os.Link(src, dst); err == nil {
		return os.Remove(src)
	} else if !os.IsExist(err) {
		if copyErr := copyFileExclusive(src, dst); copyErr != nil {
			if !errors.Is(copyErr, ErrDestinationExists) {
				return copyErr
			}
		} else {
			return os.Remove(src)
		}
	}
	return fmt.Errorf("%w: %s", ErrDestinationExists, dst)
}

// copyFileExclusive копирует файл, отказываясь трогать существующий dst.
func copyFileExclusive(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
	if err != nil {
		if os.IsExist(err) {
			return fmt.Errorf("%w: %s", ErrDestinationExists, dst)
		}
		return err
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		os.Remove(dst)
		return copyErr
	}
	if closeErr != nil {
		os.Remove(dst)
		return closeErr
	}
	return nil
}

// sweepLoop периодически удаляет старую историю терминальных заданий.
func (q *TranscodeQueue) sweepLoop() {
	defer q.wg.Done()
	ticker := time.NewTicker(transcodeSweepInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			q.sweepTerminal()
		case <-q.ctx.Done():
			return
		}
	}
}

// sweepTerminal удаляет терминальную историю старше TTL, но done-задания
// с существующим исходником не трогает: без строки теряется связь
// оригинала с Media, и файл выпадает из авточистки навсегда.
// Keyset-проход (afterID): пропущенные done не блокируют чистку остальных,
// сколько бы их ни было.
func (q *TranscodeQueue) sweepTerminal() {
	ctx := context.Background()
	cutoff := time.Now().Add(-TranscodeTerminalTTL)
	var afterID uint
	for {
		tasks, err := q.tasks.ListTerminalBefore(ctx, cutoff, afterID,
			transcodeSweepBatch, TranscodeTaskDone, TranscodeTaskError, TranscodeTaskCancelled)
		if err != nil {
			log.Printf("transcode: sweep list terminal: %v", err)
			return
		}
		if len(tasks) == 0 {
			return
		}
		var ids []uint
		for _, task := range tasks {
			if task.Status == TranscodeTaskDone {
				if _, err := os.Stat(task.SourcePath); err == nil {
					continue
				}
			}
			ids = append(ids, task.ID)
		}
		if len(ids) > 0 {
			if err := q.tasks.DeleteByIDs(ctx, ids); err != nil {
				log.Printf("transcode: sweep delete terminal: %v", err)
				return
			}
		}
		afterID = tasks[len(tasks)-1].ID
		if len(tasks) < transcodeSweepBatch {
			return
		}
	}
}
