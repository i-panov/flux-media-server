package services

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

// Внутренние тесты UploadQueue: доступ к приватным полям (статусы,
// createdAt, sweep) нужен для детерминированной проверки TTL-очистки
// и семантики fail/cancel без ожидания реального часа.

func setupUploadTestQueue(t *testing.T, limit int) (*UploadQueue, repository.MediaRepository) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	thumbSvc := NewThumbnailService(t.TempDir())
	q := NewUploadQueue(context.Background(), mediaRepo, repository.NewUploadTaskRepository(db), thumbSvc, 0, limit)
	t.Cleanup(q.Stop)
	return q, mediaRepo
}

func enqueueTestJob(t *testing.T, q *UploadQueue, name string) *UploadJob {
	t.Helper()

	dir := t.TempDir()
	path := filepath.Join(dir, name)
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))

	id, err := q.Enqueue(UploadJobInput{FilePath: path, Filename: name, MediaType: models.MediaTypeVideo})
	require.NoError(t, err)

	q.mu.Lock()
	defer q.mu.Unlock()
	job, ok := q.jobs[id]
	require.True(t, ok)
	return job
}

// setJobTerminal переводит задание в терминальный статус с заданным
// временем создания (для проверки TTL без ожидания часа).
func setJobTerminal(t *testing.T, q *UploadQueue, job *UploadJob, status string, createdAt time.Time) {
	t.Helper()

	q.mu.Lock()
	defer q.mu.Unlock()
	job.Status = status
	job.createdAt = createdAt
}

// TestUploadQueueSweepRemovesExpiredTerminal: терминальные задания старше
// TTL удаляются, клиентский Get после этого возвращает not found.
func TestUploadQueueSweepRemovesExpiredTerminal(t *testing.T) {
	q, _ := setupUploadTestQueue(t, 10)

	job := enqueueTestJob(t, q, "a.mp4")
	setJobTerminal(t, q, job, UploadJobDone, time.Now().Add(-2*uploadJobTTL))

	q.sweep()

	_, _, _, ok := q.Get(job.ID)
	assert.False(t, ok, "expired terminal job must be swept")
}

// TestUploadQueueSweepKeepsActiveAndRecent: активные задания не удаляются
// независимо от возраста; свежие терминальные остаются для опроса статуса.
func TestUploadQueueSweepKeepsActiveAndRecent(t *testing.T) {
	q, _ := setupUploadTestQueue(t, 10)

	oldActive := enqueueTestJob(t, q, "active.mp4")
	setJobTerminal(t, q, oldActive, UploadJobQueued, time.Now().Add(-2*uploadJobTTL))

	recentDone := enqueueTestJob(t, q, "done.mp4")
	setJobTerminal(t, q, recentDone, UploadJobDone, time.Now())

	q.sweep()

	_, _, _, ok := q.Get(oldActive.ID)
	assert.True(t, ok, "active job must never be swept")
	_, _, _, ok = q.Get(recentDone.ID)
	assert.True(t, ok, "recent terminal job must be kept for status polling")
}

// TestUploadQueueSweepHardCap: даже свежие терминальные задания не копятся
// бесконечно — при превышении maxKeptJobs удаляются старейшие терминальные.
func TestUploadQueueSweepHardCap(t *testing.T) {
	total := maxKeptJobs + 50
	q, _ := setupUploadTestQueue(t, total+10)

	for i := 0; i < total; i++ {
		job := enqueueTestJob(t, q, fmt.Sprintf("f%d.mp4", i))
		// Свежие терминальные (TTL не истёк) — чистка возможна только по потолку.
		setJobTerminal(t, q, job, UploadJobDone, time.Now().Add(-time.Duration(total-i)*time.Second))
	}

	q.sweep()

	q.mu.Lock()
	count := len(q.jobs)
	q.mu.Unlock()
	assert.LessOrEqual(t, count, maxKeptJobs, "jobs map must be capped")
}

// TestUploadQueueFailDoesNotOverwriteCancelled: fail воркера по уже
// отменённому заданию не перезаписывает статус и не паникует.
func TestUploadQueueFailDoesNotOverwriteCancelled(t *testing.T) {
	q, _ := setupUploadTestQueue(t, 10)

	job := enqueueTestJob(t, q, "cancel.mp4")
	require.NoError(t, q.Cancel(job.ID))

	q.fail(job, errors.New("worker exploded"), "Failed to process file")

	assert.Equal(t, uploadJobCancelled, job.Status, "cancelled status must not be overwritten by fail")

	_, _, _, ok := q.Get(job.ID)
	assert.False(t, ok, "cancelled job stays removed from the map")
}

// TestUploadQueueCancelCleansUpResources: Cancel удаляет файл и запись
// Media (если создана) — вне мьютекса, но с тем же эффектом.
func TestUploadQueueCancelCleansUpResources(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)

	job := enqueueTestJob(t, q, "cleanup.mp4")

	// Имитируем созданную воркером запись Media.
	ctx := context.Background()
	media := &models.Media{Title: "t", Type: models.MediaTypeVideo, FilePath: job.filePath}
	require.NoError(t, mediaRepo.Create(ctx, media))
	q.mu.Lock()
	job.MediaID = media.ID
	q.mu.Unlock()

	require.NoError(t, q.Cancel(job.ID))

	_, err := os.Stat(job.filePath)
	assert.True(t, os.IsNotExist(err), "file must be removed on cancel")
	_, err = mediaRepo.FindByID(ctx, media.ID)
	assert.Error(t, err, "media record must be removed on cancel")
}

// blockingCreateRepo задерживает воркера внутри Create (после вставки
// записи, до возврата): Cancel гарантированно попадает в середину process.
type blockingCreateRepo struct {
	*repository.MediaStore
	release chan struct{}
}

func (r *blockingCreateRepo) Create(ctx context.Context, media *models.Media) error {
	if err := r.MediaStore.Create(ctx, media); err != nil {
		return err
	}
	<-r.release
	return nil
}

// TestUploadQueueCancelDuringProcessingNoRace: Cancel во время обработки
// воркером не гоняется за записи job.MediaID — снапшот ресурсов снимается
// под q.mu (ловится go test -race). Воркер детерминированно остановлен
// внутри Create, так что Cancel всегда застаёт задание в processing.
func TestUploadQueueCancelDuringProcessingNoRace(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	release := make(chan struct{})
	mediaRepo := &blockingCreateRepo{MediaStore: repository.NewMediaRepository(db), release: release}
	thumbSvc := NewThumbnailService(t.TempDir())
	q := NewUploadQueue(context.Background(), mediaRepo, repository.NewUploadTaskRepository(db), thumbSvc, 1, 10)
	t.Cleanup(q.Stop)

	dir := t.TempDir()
	path := filepath.Join(dir, "race.mp4")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))

	id, err := q.Enqueue(UploadJobInput{FilePath: path, Filename: "race.mp4", MediaType: models.MediaTypeVideo})
	require.NoError(t, err)

	// Воркер гарантированно внутри process (задержан в Create) — Cancel
	// застаёт статус processing, а не done.
	time.Sleep(100 * time.Millisecond)
	require.NoError(t, q.Cancel(id))

	// Отпускаем воркера: запись job.MediaID и снапшоты после Cancel
	// проверяются детектором гонок.
	close(release)
	time.Sleep(200 * time.Millisecond)

	_, _, _, ok := q.Get(id)
	assert.False(t, ok, "cancelled job stays removed from the map")
}

// TestUploadQueueDuplicateStatus: похожий мем фиксируется в статусе
// duplicate, а файл и запись новой загрузки удаляются.
func TestUploadQueueDuplicateStatus(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)
	ctx := context.Background()

	existing := &models.Media{
		Title:    "Старый мем",
		Type:     models.MediaTypeImage,
		FilePath: filepath.Join(t.TempDir(), "old.png"),
	}
	require.NoError(t, mediaRepo.Create(ctx, existing))

	job := enqueueTestJob(t, q, "new.png")
	newMedia := &models.Media{
		Title:    "Новый мем",
		Type:     models.MediaTypeImage,
		FilePath: job.filePath,
	}
	require.NoError(t, mediaRepo.Create(ctx, newMedia))

	q.mu.Lock()
	job.mediaType = models.MediaTypeImage
	job.MediaID = newMedia.ID
	q.mu.Unlock()

	q.duplicate(job, existing)

	status, ok := q.Status(job.ID)
	require.True(t, ok)
	assert.Equal(t, UploadJobDuplicate, status.Status)
	assert.Equal(t, existing.ID, status.DuplicateMediaID)
	assert.Equal(t, existing.Title, status.DuplicateTitle)

	_, err := os.Stat(job.filePath)
	assert.True(t, os.IsNotExist(err), "файл дубля удалён")
	_, err = mediaRepo.FindByID(ctx, newMedia.ID)
	assert.Error(t, err, "запись дубля удалена")
}

// TestUploadQueueConcurrentSimilarUploadsKeepOne: два воркера с похожими
// картинками не должны счесть дублями друг друга и удалить обе.
func TestUploadQueueConcurrentSimilarUploadsKeepOne(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)
	ctx := context.Background()
	dir := t.TempDir()

	createMedia := func(title string) (*models.Media, string) {
		path := filepath.Join(dir, title+".png")
		require.NoError(t, os.WriteFile(path, []byte("image"), 0644))
		media := &models.Media{
			Title:    title,
			Type:     models.MediaTypeImage,
			FilePath: path,
		}
		require.NoError(t, mediaRepo.Create(ctx, media))
		return media, path
	}

	mediaA, pathA := createMedia("a")
	mediaB, pathB := createMedia("b")
	const phash int64 = 0x0F0F_0F0F_0F0F_0F0F
	require.NoError(t, mediaRepo.SetPHash(ctx, mediaA.ID, phash))
	require.NoError(t, mediaRepo.SetPHash(ctx, mediaB.ID, phash^0x3))

	jobs := []*UploadJob{
		{
			ID:        1,
			Status:    UploadJobProcessing,
			filePath:  pathA,
			mediaType: models.MediaTypeImage,
			MediaID:   mediaA.ID,
		},
		{
			ID:        2,
			Status:    UploadJobProcessing,
			filePath:  pathB,
			mediaType: models.MediaTypeImage,
			MediaID:   mediaB.ID,
		},
	}

	start := make(chan struct{})
	type result struct {
		duplicate bool
		err       error
	}
	results := make(chan result, len(jobs))
	for _, job := range jobs {
		go func(j *UploadJob) {
			<-start
			duplicate, err := q.resolveDuplicate(ctx, j, phash)
			results <- result{duplicate: duplicate, err: err}
		}(job)
	}
	close(start)

	duplicates := 0
	for range jobs {
		res := <-results
		require.NoError(t, res.err)
		if res.duplicate {
			duplicates++
		}
	}
	assert.Equal(t, 1, duplicates, "дублем должен оказаться ровно один файл")

	left, _, err := mediaRepo.FindAll(ctx, repository.MediaFilters{
		Type: models.MediaTypeImage,
	}, 10, 0)
	require.NoError(t, err)
	assert.Len(t, left, 1, "в библиотеке должен остаться один мем")
}

// TestUploadQueueParallelSameContentKeepsOne: две параллельные заливки
// одного контента под разными именами (дедуп по file_path их не ловит)
// дают ровно одну Media-строку: младший дубликат выходит той же ошибкой,
// что поздняя проверка по Media, старший идёт дальше. Без ffmpeg:
// реальный хэш и реальные строки, вызывается production-ветка
// checkParallelDuplicate (моков тяжёлых шагов нет).
func TestUploadQueueParallelSameContentKeepsOne(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)
	ctx := context.Background()
	dir := t.TempDir()

	content := []byte("same-content-for-parallel-uploads")
	pathA := filepath.Join(dir, "a.mp4")
	pathB := filepath.Join(dir, "other-name.mp4")
	require.NoError(t, os.WriteFile(pathA, content, 0644))
	require.NoError(t, os.WriteFile(pathB, content, 0644))

	idA, err := q.Enqueue(UploadJobInput{FilePath: pathA, Filename: "a.mp4", MediaType: models.MediaTypeVideo})
	require.NoError(t, err)
	idB, err := q.Enqueue(UploadJobInput{FilePath: pathB, Filename: "other-name.mp4", MediaType: models.MediaTypeVideo})
	require.NoError(t, err)
	require.Less(t, idA, idB, "старший ID выигрывает детерминированно")

	// Оба воркера честно хэшируют свой файл (без ffmpeg): хэши обязаны сойтись.
	hashA, err := HashFileContext(ctx, pathA)
	require.NoError(t, err)
	require.NotEmpty(t, hashA)
	hashB, err := HashFileContext(ctx, pathB)
	require.NoError(t, err)
	assert.Equal(t, hashA, hashB, "одинаковый контент обязан давать одинаковый хэш")

	q.mu.Lock()
	jobA := q.jobs[idA]
	jobB := q.jobs[idB]
	q.mu.Unlock()
	require.NotNil(t, jobA)
	require.NotNil(t, jobB)

	// Оба сохраняют хэш в свои строки — точка, после которой в process
	// идёт новая проверка.
	q.saveFileHash(jobA, hashA)
	q.saveFileHash(jobB, hashB)

	// Параллельный прогон проверочной ветки (production-код): порядок
	// завершения не важен, исход детерминирован старшинством ID.
	start := make(chan struct{})
	results := make(chan bool, 2)
	go func() { <-start; results <- q.checkParallelDuplicate(jobA, hashA) }()
	go func() { <-start; results <- q.checkParallelDuplicate(jobB, hashB) }()
	close(start)
	finished := 0
	for range 2 {
		if <-results {
			finished++
		}
	}
	assert.Equal(t, 1, finished, "ровно одно задание обязано выйти дубликатом")

	// Старший идёт дальше (активен, файл цел), младший — в ошибке тем же
	// сообщением, что поздняя проверка по Media, файл удалён.
	statusA, _, _, ok := q.Get(idA)
	require.True(t, ok)
	assert.NotEqual(t, UploadJobError, statusA, "старший не должен упасть")
	assert.FileExists(t, pathA)

	statusB, errMsgB, mediaIDB, ok := q.Get(idB)
	require.True(t, ok)
	assert.Equal(t, UploadJobError, statusB)
	assert.Equal(t, "File already exists", errMsgB, "та же ошибка, что поздняя проверка по Media")
	assert.Zero(t, mediaIDB, "проигравший не создаёт запись")
	assert.NoFileExists(t, pathB)

	// Старший доводит Create до конца (чистый INSERT без ffmpeg):
	// в библиотеке ровно одна строка, от проигравшего — ни одной.
	elderMedia := &models.Media{
		Title:    "a",
		Filename: "a.mp4",
		Type:     models.MediaTypeVideo,
		FilePath: pathA,
		FileHash: hashA,
	}
	require.NoError(t, mediaRepo.Create(ctx, elderMedia))
	all, _, err := mediaRepo.FindAll(ctx, repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	assert.Len(t, all, 1, "в библиотеке обязана остаться ровно одна строка")
}

// slowFindByHashRepo расширяет окно гонки позднего гейта: FindByHash спит,
// пока соседний воркер тоже добирается до проверки. Без fileHashMu обе
// проверки вернули бы nil и создали бы два дубля; с мьютексом второй видит
// строку первого. Без ffmpeg: только БД-операции production-ветки
// checkAndCreateMedia.
type slowFindByHashRepo struct {
	repository.MediaRepository
	delay time.Duration
}

func (r *slowFindByHashRepo) FindByHash(ctx context.Context, hash string) (*models.Media, error) {
	time.Sleep(r.delay)
	return r.MediaRepository.FindByHash(ctx, hash)
}

// TestUploadQueueLateExactDuplicateGateKeepsOne: оба воркера прошли раннюю
// проверку (здесь она пропущена — вызывается только поздний гейт, как при
// обоюдном проходе), поздний гейт детерминирован: первый создаёт, второй
// уходит в тот же failDuplicateUpload. Детерминирован при любом
// планировании: проверки сериализованы мьютексом, второй FindByHash всегда
// идёт после первого Create (ловится go test -race).
func TestUploadQueueLateExactDuplicateGateKeepsOne(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := &slowFindByHashRepo{MediaRepository: repository.NewMediaRepository(db), delay: 200 * time.Millisecond}
	thumbSvc := NewThumbnailService(t.TempDir())
	q := NewUploadQueue(context.Background(), mediaRepo, repository.NewUploadTaskRepository(db), thumbSvc, 0, 10)
	t.Cleanup(q.Stop)

	dir := t.TempDir()
	mkJob := func(name string) *UploadJob {
		path := filepath.Join(dir, name)
		require.NoError(t, os.WriteFile(path, []byte("x"), 0644))
		id, err := q.Enqueue(UploadJobInput{FilePath: path, Filename: name, MediaType: models.MediaTypeVideo})
		require.NoError(t, err)
		q.mu.Lock()
		defer q.mu.Unlock()
		job, ok := q.jobs[id]
		require.True(t, ok)
		return job
	}
	jobA := mkJob("a.mp4")
	jobB := mkJob("other-name.mp4")

	// Один хэш на оба задания: файлы разные, контент один.
	const hash = "same-content-hash"

	start := make(chan struct{})
	type outcome struct {
		media   *models.Media
		handled bool
	}
	jobs := []*UploadJob{jobA, jobB}
	outcomes := make([]outcome, len(jobs))
	var wg sync.WaitGroup
	for i, job := range jobs {
		wg.Add(1)
		go func(i int, job *UploadJob) {
			defer wg.Done()
			<-start
			media, handled := q.checkAndCreateMedia(job, hash)
			outcomes[i] = outcome{media: media, handled: handled}
		}(i, job)
	}
	close(start)
	wg.Wait()

	winnerIdx := -1
	for i, o := range outcomes {
		if !o.handled {
			require.NotNil(t, o.media, "победитель обязан вернуть запись")
			winnerIdx = i
		} else {
			assert.Nil(t, o.media, "проигравший не создаёт запись")
		}
	}
	require.NotEqual(t, -1, winnerIdx, "ровно один воркер обязан создать запись")
	loserIdx := 1 - winnerIdx
	winner, loser := jobs[winnerIdx], jobs[loserIdx]

	all, _, err := repository.NewMediaRepository(db).FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, all, 1, "в библиотеке обязана остаться ровно одна строка")
	assert.Equal(t, hash, all[0].FileHash)
	assert.Equal(t, all[0].ID, outcomes[winnerIdx].media.ID)

	// Проигравший — в той же ошибке дубликата, что ранняя проверка, файл удалён.
	status, errMsg, mediaID, ok := q.Get(loser.ID)
	require.True(t, ok)
	assert.Equal(t, UploadJobError, status)
	assert.Equal(t, "File already exists", errMsg, "та же ошибка, что ранняя проверка по строкам")
	assert.Zero(t, mediaID, "проигравший не фиксирует MediaID")
	assert.NoFileExists(t, loser.filePath)
	assert.FileExists(t, winner.filePath)
}

// TestUploadQueueLateDuplicateAfterElderDone: старший довёл process до done
// (строка задач уже не активна — ранняя проверка младшего её не видит),
// младший с тем же контентом проходит раннюю проверку и ловится поздним
// гейтом по Media. Полный production-путь без ffmpeg: битый контент даёт
// пустые метаданные/превью, но дедуп обязан сработать раньше. Старший
// падает позже — оба в error, лечится ретраем (см. checkParallelDuplicate).
func TestUploadQueueLateDuplicateAfterElderDone(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)
	ctx := context.Background()
	dir := t.TempDir()

	content := []byte("same-content-for-late-gate")
	pathElder := filepath.Join(dir, "elder.mp4")
	pathJunior := filepath.Join(dir, "junior.mp4")
	require.NoError(t, os.WriteFile(pathElder, content, 0644))
	require.NoError(t, os.WriteFile(pathJunior, content, 0644))

	idElder, err := q.Enqueue(UploadJobInput{FilePath: pathElder, Filename: "elder.mp4", MediaType: models.MediaTypeVideo})
	require.NoError(t, err)
	idJunior, err := q.Enqueue(UploadJobInput{FilePath: pathJunior, Filename: "junior.mp4", MediaType: models.MediaTypeVideo})
	require.NoError(t, err)

	q.mu.Lock()
	elder, okElder := q.jobs[idElder]
	junior, okJunior := q.jobs[idJunior]
	q.mu.Unlock()
	require.True(t, okElder)
	require.True(t, okJunior)

	q.process(elder)
	status, _, elderMediaID, ok := q.Get(idElder)
	require.True(t, ok)
	require.Equal(t, UploadJobDone, status, "старший обязан дойти до done")
	require.NotZero(t, elderMediaID)

	q.process(junior)
	status, errMsg, mediaID, ok := q.Get(idJunior)
	require.True(t, ok)
	assert.Equal(t, UploadJobError, status)
	assert.Equal(t, "File already exists", errMsg)
	assert.Zero(t, mediaID)
	assert.NoFileExists(t, pathJunior)
	assert.FileExists(t, pathElder)

	all, _, err := mediaRepo.FindAll(ctx, repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, all, 1, "в библиотеке обязана остаться ровно одна строка")
	assert.Equal(t, elderMediaID, all[0].ID)
}

// TestUploadQueueProcessDropsJobMissingFromMap: задание, удалённое из
// карты Cancel'ом, пока ждало воркера, дропается без хэша/дедупа/создания:
// записи Media нет, файл не тронут (его уже убрал Cancel).
func TestUploadQueueProcessDropsJobMissingFromMap(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)

	job := enqueueTestJob(t, q, "cancelled.mp4")
	path := job.filePath
	q.mu.Lock()
	delete(q.jobs, job.ID)
	q.mu.Unlock()

	q.process(job)

	all, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	assert.Empty(t, all, "дропнутое задание не должно создавать запись Media")
	assert.FileExists(t, path, "дропнутое задание не должно трогать файл")
}

// TestUploadQueueProcessDropsEarlyCancelled: задание со статусом cancelled,
// всё ещё висящее в карте, тоже выходит до saveStatus и HashFileContext.
func TestUploadQueueProcessDropsEarlyCancelled(t *testing.T) {
	q, mediaRepo := setupUploadTestQueue(t, 10)

	job := enqueueTestJob(t, q, "early.mp4")
	path := job.filePath
	q.mu.Lock()
	job.Status = uploadJobCancelled
	q.mu.Unlock()

	q.process(job)

	all, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	assert.Empty(t, all, "отменённое задание не должно создавать запись Media")
	assert.FileExists(t, path, "отменённое до старта задание не должно трогать файл")
}
