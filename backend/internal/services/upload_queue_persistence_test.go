package services

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

// Управляемый рестарт (SIGTERM → Stop) не должен хоронить летящее
// задание в error: fail при мёртвом q.ctx возвращает строку в queued,
// следующий старт подхватывает её через recovery. Живой контекст
// по-прежнему пишет терминальный error. Зеркалит
// TestExtractFail_RequeuesOnShutdown.
func TestUploadFail_RequeuesOnShutdown(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	newQueue := func() *UploadQueue {
		return NewUploadQueue(
			context.Background(),
			repository.NewMediaRepository(db),
			repository.NewUploadTaskRepository(db),
			NewThumbnailService(t.TempDir()),
			0, 10,
		)
	}

	q := newQueue()
	dir := t.TempDir()
	path := filepath.Join(dir, "a.mp3")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))
	id, err := q.Enqueue(UploadJobInput{FilePath: path, Filename: "a.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	q.mu.Lock()
	job := q.jobs[id]
	q.mu.Unlock()

	// Файл обязан пережить shutdown-requeue: fail не чистит ресурсы.
	q.cancel()
	q.fail(job, context.Canceled, "boom")

	status, errMsg, _, ok := q.Get(id)
	require.True(t, ok)
	assert.Equal(t, UploadJobQueued, status)
	assert.Empty(t, errMsg)
	assert.FileExists(t, path)
	q.Stop()

	// Контроль: живой контекст по-прежнему пишет терминальный error
	// и удаляет файл.
	q2 := newQueue()
	t.Cleanup(q2.Stop)
	path2 := filepath.Join(t.TempDir(), "b.mp3")
	require.NoError(t, os.WriteFile(path2, []byte("content"), 0644))
	other, err := q2.Enqueue(UploadJobInput{FilePath: path2, Filename: "b.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	q2.mu.Lock()
	otherJob := q2.jobs[other]
	q2.mu.Unlock()
	q2.fail(otherJob, assert.AnError, "boom")

	status, errMsg, _, ok = q2.Get(other)
	require.True(t, ok)
	assert.Equal(t, UploadJobError, status)
	assert.Equal(t, "boom", errMsg)
	assert.NoFileExists(t, path2)
}

// Перезапуск сервера поднимает незавершённые задания из БД: processing
// сбрасывается в queued, ID стабильны (из БД), дедуп по файлу работает
// и для поднятых заданий, отмена чистит и строку. Зеркалит
// TestExtractService_RestartRecovery.
func TestUploadQueue_RestartRecovery(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	ctx := context.Background()
	newQueue := func() *UploadQueue {
		return NewUploadQueue(
			context.Background(),
			repository.NewMediaRepository(db),
			repository.NewUploadTaskRepository(db),
			NewThumbnailService(t.TempDir()),
			0, 10,
		)
	}

	q1 := newQueue()
	dir := t.TempDir()
	path := filepath.Join(dir, "song.mp3")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))
	id1, err := q1.Enqueue(UploadJobInput{FilePath: path, Filename: "song.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	require.NotZero(t, id1)
	// Имитация краха посреди обработки: строка осталась processing.
	store := repository.NewUploadTaskRepository(db)
	require.NoError(t, store.SetStatus(ctx, id1, UploadJobProcessing, "", 0))
	q1.Stop()

	q2 := newQueue()
	t.Cleanup(q2.Stop)

	status, _, _, ok := q2.Get(id1)
	require.True(t, ok, "recovered job must be visible")
	assert.Equal(t, UploadJobQueued, status)

	row, err := store.Get(ctx, id1)
	require.NoError(t, err)
	assert.Equal(t, UploadJobQueued, row.Status)
	assert.Equal(t, path, row.FilePath)
	assert.Equal(t, "song.mp3", row.Filename)

	// Дедуп видит поднятое задание: повторный POST того же файла отдаёт
	// тот же ID, а не плодит второе задание.
	dup, err := q2.Enqueue(UploadJobInput{FilePath: path, Filename: "song.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	assert.Equal(t, id1, dup)

	// Новые задания продолжают счётчик БД, а не занимают старые ID.
	path2 := filepath.Join(t.TempDir(), "other.mp3")
	require.NoError(t, os.WriteFile(path2, []byte("other"), 0644))
	id2, err := q2.Enqueue(UploadJobInput{FilePath: path2, Filename: "other.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	assert.Greater(t, id2, id1)

	// Отмена удаляет и строку.
	require.NoError(t, q2.Cancel(id1))
	_, _, _, ok = q2.Get(id1)
	assert.False(t, ok)
	_, err = store.Get(ctx, id1)
	require.Error(t, err)
	assert.NoFileExists(t, path)
}

// Дедуп по файлу при recovery: два unfinished на один путь — след двойной
// постановки до краха, остаётся старейший.
func TestUploadQueue_RecoveryDedupsByFile(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	ctx := context.Background()
	store := repository.NewUploadTaskRepository(db)

	path := filepath.Join(t.TempDir(), "same.mp3")
	first := &models.UploadTask{FilePath: path, Filename: "same.mp3", MediaType: models.MediaTypeAudio, Status: UploadJobQueued}
	require.NoError(t, store.Create(ctx, first))
	second := &models.UploadTask{FilePath: path, Filename: "same.mp3", MediaType: models.MediaTypeAudio, Status: UploadJobQueued}
	require.NoError(t, store.Create(ctx, second))

	q := NewUploadQueue(
		context.Background(),
		repository.NewMediaRepository(db),
		store,
		NewThumbnailService(t.TempDir()),
		0, 10,
	)
	t.Cleanup(q.Stop)

	q.mu.Lock()
	count := len(q.jobs)
	_, hasFirst := q.jobs[first.ID]
	_, hasSecond := q.jobs[second.ID]
	q.mu.Unlock()
	assert.Equal(t, 1, count)
	assert.True(t, hasFirst, "oldest job must survive")
	assert.False(t, hasSecond, "duplicate path must be dropped")
	_, err = store.Get(ctx, second.ID)
	assert.Error(t, err)
}

// Статус переживает рестарт через БД: терминальные (done) строки не
// поднимаются в карту, но Status отдаёт их из БД до sweep.
func TestUploadQueue_StatusSurvivesRestart(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	ctx := context.Background()
	newQueue := func() *UploadQueue {
		return NewUploadQueue(
			context.Background(),
			repository.NewMediaRepository(db),
			repository.NewUploadTaskRepository(db),
			NewThumbnailService(t.TempDir()),
			0, 10,
		)
	}

	q1 := newQueue()
	path := filepath.Join(t.TempDir(), "done.mp3")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))
	id, err := q1.Enqueue(UploadJobInput{FilePath: path, Filename: "done.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)
	store := repository.NewUploadTaskRepository(db)
	require.NoError(t, store.SetStatus(ctx, id, UploadJobDone, "", 42))
	q1.Stop()

	q2 := newQueue()
	t.Cleanup(q2.Stop)

	snap, ok := q2.Status(id)
	require.True(t, ok, "terminal status must survive restart via DB")
	assert.Equal(t, UploadJobDone, snap.Status)
	assert.Equal(t, uint(42), snap.MediaID)
}

// Sweep выметает и строки БД: клиент после TTL видит 404, а не воскресшую
// строку после рестарта. Зеркалит extract sweep.
func TestUploadQueue_SweepDeletesDBRows(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	store := repository.NewUploadTaskRepository(db)
	q := NewUploadQueue(
		context.Background(),
		repository.NewMediaRepository(db),
		store,
		NewThumbnailService(t.TempDir()),
		0, 10,
	)
	t.Cleanup(q.Stop)

	path := filepath.Join(t.TempDir(), "old.mp3")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))
	id, err := q.Enqueue(UploadJobInput{FilePath: path, Filename: "old.mp3", MediaType: models.MediaTypeAudio})
	require.NoError(t, err)

	q.mu.Lock()
	job := q.jobs[id]
	job.Status = UploadJobDone
	job.createdAt = time.Now().Add(-2 * uploadJobTTL)
	q.mu.Unlock()
	require.NoError(t, store.SetStatus(context.Background(), id, UploadJobDone, "", 0))

	q.sweep()

	_, _, _, ok := q.Get(id)
	assert.False(t, ok)
	_, err = store.Get(context.Background(), id)
	assert.Error(t, err)
}
