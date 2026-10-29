package services

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
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
	q := NewUploadQueue(context.Background(), mediaRepo, thumbSvc, 0, limit)
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
	q := NewUploadQueue(context.Background(), mediaRepo, thumbSvc, 1, 10)
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
