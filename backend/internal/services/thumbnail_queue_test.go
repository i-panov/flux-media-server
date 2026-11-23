package services

import (
	"context"
	"os"
	"testing"

	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func TestThumbnailQueueEnqueueCoversAdvancesCursor(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	for i := 0; i < 150; i++ {
		row := models.Media{
			Title:    "track",
			Type:     models.MediaTypeAudio,
			FilePath: "/tmp/track.mp3",
		}
		require.NoError(t, mediaRepo.Create(context.Background(), &row))
	}
	store := repository.NewThumbnailRepository(db)
	queue := NewThumbnailQueueService(store, mediaRepo, nil)

	// Без курсора цикл на 150 записях зацикливался бы на первых 100.
	require.NoError(t, queue.EnqueueMissing(context.Background(), models.ThumbnailKindCover))
	pending, err := store.Pending(context.Background(), models.ThumbnailKindCover)
	require.NoError(t, err)
	require.Equal(t, int64(150), pending)
}

func TestThumbnailQueueRequeuesStaleProcessing(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	store := repository.NewThumbnailRepository(db)
	ctx := context.Background()
	require.NoError(t, store.Enqueue(ctx, 1, models.ThumbnailKindThumb))
	_, err = store.NextQueued(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)

	requeued, err := store.RequeueProcessing(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Equal(t, int64(1), requeued)

	task, err := store.NextQueued(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Equal(t, uint(1), task.MediaID)
}

func TestThumbnailQueueRunIgnoresOtherKind(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	store := repository.NewThumbnailRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	queue := NewThumbnailQueueService(store, mediaRepo, nil)
	ctx := context.Background()
	require.NoError(t, store.Enqueue(ctx, 1, models.ThumbnailKindCover))

	generated, failed := queue.Run(ctx, models.ThumbnailKindThumb)
	require.Zero(t, generated)
	require.Zero(t, failed)
	pending, err := store.Pending(ctx, models.ThumbnailKindCover)
	require.NoError(t, err)
	require.Equal(t, int64(1), pending, "чужая задача остаётся в очереди")
}

func TestThumbnailQueueRestoresLostURL(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	ctx := context.Background()
	row := models.Media{
		Title: "video", Type: models.MediaTypeVideo, FilePath: "/tmp/video.mp4",
		VideoKind: func() *models.VideoKind { k := models.VideoKindMovie; return &k }(),
	}
	require.NoError(t, mediaRepo.Create(ctx, &row))

	dir := t.TempDir()
	thumb := NewThumbnailService(dir)
	require.NoError(t, os.MkdirAll(dir, 0o750))
	require.NoError(t, os.WriteFile(thumb.GetPath(row.ID), []byte("thumb"), 0o600))

	store := repository.NewThumbnailRepository(db)
	queue := NewThumbnailQueueService(store, mediaRepo, thumb)
	require.NoError(t, queue.EnqueueMissing(ctx, models.ThumbnailKindThumb))
	generated, failed := queue.Run(ctx, models.ThumbnailKindThumb)
	require.Equal(t, 1, generated)
	require.Zero(t, failed)

	stored, err := mediaRepo.FindByID(ctx, row.ID)
	require.NoError(t, err)
	require.NotEmpty(t, stored.ThumbnailURL, "потерянный URL восстановлен")
}
