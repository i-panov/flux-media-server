package repository

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

func TestTranscodeTaskStore_Lifecycle(t *testing.T) {
	db := fileDB(t)
	store := NewTranscodeTaskRepository(db)
	ctx := context.Background()

	task := &models.TranscodeTask{SourcePath: "/q/a.mkv", Filename: "a.mkv", Status: "queued"}
	require.NoError(t, store.Create(ctx, task))
	require.NotZero(t, task.ID)

	// Claim забирает старейшее queued ровно один раз.
	claimed, err := store.ClaimNextQueued(ctx, "queued", "processing")
	require.NoError(t, err)
	assert.Equal(t, task.ID, claimed.ID)
	assert.Equal(t, "processing", claimed.Status)

	_, err = store.ClaimNextQueued(ctx, "queued", "processing")
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)

	// Update + Get.
	claimed.Progress = 42
	require.NoError(t, store.Update(ctx, claimed))
	got, err := store.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, 42, got.Progress)

	// FindLatestBySourcePath.
	latest, err := store.FindLatestBySourcePath(ctx, "/q/a.mkv")
	require.NoError(t, err)
	assert.Equal(t, task.ID, latest.ID)
	_, err = store.FindLatestBySourcePath(ctx, "/q/nope.mkv")
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)
}

func TestTranscodeTaskStore_ResetStuck(t *testing.T) {
	db := fileDB(t)
	store := NewTranscodeTaskRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.TranscodeTask{SourcePath: "/q/a.mkv", Status: "processing"}))
	require.NoError(t, store.Create(ctx, &models.TranscodeTask{SourcePath: "/q/b.mkv", Status: "queued"}))
	done := &models.TranscodeTask{SourcePath: "/q/c.mkv", Status: "done"}
	require.NoError(t, store.Create(ctx, done))

	n, err := store.ResetStuckProcessing(ctx, "processing", "queued")
	require.NoError(t, err)
	assert.Equal(t, int64(1), n)

	got, err := store.Get(ctx, done.ID)
	require.NoError(t, err)
	assert.Equal(t, "done", got.Status)
}

func TestTranscodeTaskStore_Sweep(t *testing.T) {
	db := fileDB(t)
	store := NewTranscodeTaskRepository(db)
	ctx := context.Background()

	old := &models.TranscodeTask{SourcePath: "/q/old.mkv", Status: "done"}
	require.NoError(t, store.Create(ctx, old))
	require.NoError(t, db.Model(old).Update("updated_at", time.Now().Add(-8*24*time.Hour)).Error)
	fresh := &models.TranscodeTask{SourcePath: "/q/fresh.mkv", Status: "done"}
	require.NoError(t, store.Create(ctx, fresh))

	n, err := store.DeleteTerminalBefore(ctx, time.Now().Add(-7*24*time.Hour), "done", "error", "cancelled")
	require.NoError(t, err)
	assert.Equal(t, int64(1), n)
	_, err = store.Get(ctx, fresh.ID)
	require.NoError(t, err)
}

func TestTranscodeTaskStore_ActiveByHash(t *testing.T) {
	db := fileDB(t)
	store := NewTranscodeTaskRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.TranscodeTask{SourcePath: "/q/a.mkv", SourceHash: "h1", Status: "processing"}))
	require.NoError(t, store.Create(ctx, &models.TranscodeTask{SourcePath: "/q/b.mkv", SourceHash: "h1", Status: "done"}))

	found, err := store.FindActiveBySourceHash(ctx, "h1", "queued", "processing")
	require.NoError(t, err)
	assert.Equal(t, "/q/a.mkv", found.SourcePath)

	_, err = store.FindActiveBySourceHash(ctx, "nope", "queued", "processing")
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)
}

func TestSubtitleStore_ReplaceAndList(t *testing.T) {
	db := fileDB(t)
	store := NewSubtitleRepository(db)
	ctx := context.Background()

	media := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: "/v.mp4"}
	require.NoError(t, NewMediaRepository(db).Create(ctx, media))

	require.NoError(t, store.ReplaceForMedia(ctx, media.ID, []models.Subtitle{
		{Lang: "rus", Path: "/v/f.rus.vtt"},
		{Lang: "eng", Path: "/v/f.eng.vtt"},
	}))
	subs, err := store.ListByMedia(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, subs, 2)
	assert.Equal(t, "eng", subs[0].Lang)
	assert.Equal(t, "rus", subs[1].Lang)

	// Замена чистит старые строки.
	require.NoError(t, store.ReplaceForMedia(ctx, media.ID, []models.Subtitle{{Lang: "deu", Path: "/v/f.deu.vtt"}}))
	subs, err = store.ListByMedia(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, subs, 1)

	require.NoError(t, store.DeleteByMedia(ctx, media.ID))
	subs, err = store.ListByMedia(ctx, media.ID)
	require.NoError(t, err)
	assert.Empty(t, subs)
}

func TestMediaStore_ViewsAndSourceHash(t *testing.T) {
	db := fileDB(t)
	store := NewMediaRepository(db)
	ctx := context.Background()

	m := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: "/v.mp4", FileHash: "fh", SourceHash: "sh"}
	require.NoError(t, store.Create(ctx, m))

	require.NoError(t, store.IncrementViews(ctx, m.ID))
	require.NoError(t, store.IncrementViews(ctx, m.ID))
	got, err := store.FindByID(ctx, m.ID)
	require.NoError(t, err)
	assert.Equal(t, uint64(2), got.ViewCount)

	found, err := store.FindBySourceHash(ctx, "sh")
	require.NoError(t, err)
	assert.Equal(t, m.ID, found.ID)
	_, err = store.FindBySourceHash(ctx, "nope")
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)
}
