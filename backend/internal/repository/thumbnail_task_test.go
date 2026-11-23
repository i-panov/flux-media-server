package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

func TestThumbnailQueueLifecycle(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewThumbnailRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Enqueue(ctx, 1, models.ThumbnailKindThumb))
	require.NoError(t, store.Enqueue(ctx, 1, models.ThumbnailKindThumb), "повтор игнорируется")

	pending, err := store.Pending(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Equal(t, int64(1), pending)

	task, err := store.NextQueued(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Equal(t, uint(1), task.MediaID)
	require.Equal(t, models.ThumbnailTaskProcessing, task.Status)

	_, err = store.NextQueued(ctx, models.ThumbnailKindThumb)
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)

	require.NoError(t, store.Finish(ctx, task.ID, models.ThumbnailTaskDone, ""))
	pending, err = store.Pending(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Zero(t, pending)

	// Завершённые не блокируют повторную постановку.
	require.NoError(t, store.ResetFinished(ctx, models.ThumbnailKindThumb))
	require.NoError(t, store.Enqueue(ctx, 1, models.ThumbnailKindThumb))
	pending, err = store.Pending(ctx, models.ThumbnailKindThumb)
	require.NoError(t, err)
	require.Equal(t, int64(1), pending)
}
