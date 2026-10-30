package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestUploadTaskStore_CRUD(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewUploadTaskRepository(db)
	ctx := context.Background()

	task := &models.UploadTask{
		FilePath:  "/audio/song.mp3",
		Filename:  "song.mp3",
		MediaType: models.MediaTypeAudio,
		Status:    "queued",
		Force:     true,
	}
	require.NoError(t, store.Create(ctx, task))
	require.NotZero(t, task.ID)

	got, err := store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, "/audio/song.mp3", got.FilePath)
	assert.Equal(t, "song.mp3", got.Filename)
	assert.Equal(t, models.MediaTypeAudio, got.MediaType)
	assert.Equal(t, "queued", got.Status)
	assert.True(t, got.Force)

	require.NoError(t, store.SetStatus(ctx, task.ID, "done", "", 9))
	got, err = store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, "done", got.Status)
	assert.Equal(t, uint(9), got.MediaID)

	require.NoError(t, store.SetFileHash(ctx, task.ID, "abc123"))
	got, err = store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, "abc123", got.FileHash)

	require.NoError(t, store.SetDuplicate(ctx, task.ID, 7, "Старый мем"))
	got, err = store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, "duplicate", got.Status)
	assert.Equal(t, uint(7), got.DuplicateMediaID)
	assert.Equal(t, "Старый мем", got.DuplicateTitle)

	require.NoError(t, store.Delete(ctx, task.ID))
	_, err = store.Get(ctx, task.ID)
	require.Error(t, err)
}

func TestUploadTaskStore_UnfinishedAndActive(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewUploadTaskRepository(db)
	ctx := context.Background()

	seed := []models.UploadTask{
		{FilePath: "/a/1.mp3", Filename: "1.mp3", MediaType: models.MediaTypeAudio, Status: "queued"},
		{FilePath: "/a/2.mp3", Filename: "2.mp3", MediaType: models.MediaTypeAudio, Status: "processing"},
		{FilePath: "/a/3.mp3", Filename: "3.mp3", MediaType: models.MediaTypeAudio, Status: "done", MediaID: 30},
		{FilePath: "/a/4.mp3", Filename: "4.mp3", MediaType: models.MediaTypeAudio, Status: "error", Error: "boom"},
		{FilePath: "/a/5.mp3", Filename: "5.mp3", MediaType: models.MediaTypeAudio, Status: "duplicate", DuplicateMediaID: 1},
	}
	for i := range seed {
		require.NoError(t, store.Create(ctx, &seed[i]))
	}

	unfinished, err := store.FindUnfinished(ctx, "queued", "processing")
	require.NoError(t, err)
	require.Len(t, unfinished, 2)
	assert.Equal(t, "/a/1.mp3", unfinished[0].FilePath)
	assert.Equal(t, "/a/2.mp3", unfinished[1].FilePath)

	active, err := store.FindActiveByFilePath(ctx, "/a/2.mp3", "queued", "processing")
	require.NoError(t, err)
	assert.Equal(t, seed[1].ID, active.ID)

	_, err = store.FindActiveByFilePath(ctx, "/a/3.mp3", "queued", "processing")
	require.Error(t, err)

	_, err = store.FindActiveByFilePath(ctx, "/nope.mp3", "queued", "processing")
	require.Error(t, err)

	// Дедуп по хэшу: активные с тем же контентом находятся, чужие — нет.
	require.NoError(t, store.SetFileHash(ctx, seed[0].ID, "hash1"))
	require.NoError(t, store.SetFileHash(ctx, seed[1].ID, "hash1"))
	found, err := store.FindActiveByHash(ctx, "hash1", "queued", "processing")
	require.NoError(t, err)
	require.NotNil(t, found)
	assert.Equal(t, "hash1", found.FileHash)

	_, err = store.FindActiveByHash(ctx, "missing", "queued", "processing")
	require.Error(t, err)
}
