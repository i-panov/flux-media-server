package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestMediaStore_TrashRestorePurge(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	require.NoError(t, db.Create(&models.Media{Title: "T", Type: models.MediaTypeVideo, FilePath: "/a.mkv"}).Error)

	// В корзину: живые не видят, trashed видна.
	require.NoError(t, store.Delete(ctx, 1))
	_, err = store.FindByID(ctx, 1)
	assert.Error(t, err)
	trashed, err := store.TrashedMedia(ctx, 0, 0)
	require.NoError(t, err)
	require.Len(t, trashed, 1)

	// Восстановление: запись та же (id сохранён).
	require.NoError(t, store.RestoreMedia(ctx, 1))
	got, err := store.FindByID(ctx, 1)
	require.NoError(t, err)
	assert.Equal(t, "T", got.Title)

	// Purge: строки нет даже Unscoped.
	require.NoError(t, store.Delete(ctx, 1))
	require.NoError(t, store.PurgeMedia(ctx, 1))
	_, err = store.FindTrashedMedia(ctx, 1)
	assert.Error(t, err)
}

func TestMediaStore_RestorePathConflict(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	require.NoError(t, db.Create(&models.Media{Title: "Old", Type: models.MediaTypeVideo, FilePath: "/a.mkv"}).Error)
	require.NoError(t, store.Delete(ctx, 1))
	// Пока лежало в корзине, путь заняли заново.
	require.NoError(t, db.Create(&models.Media{Title: "New", Type: models.MediaTypeVideo, FilePath: "/a.mkv"}).Error)

	assert.ErrorIs(t, store.RestoreMedia(ctx, 1), ErrPathConflict)
}

func TestMediaStore_RestoreLiveIsNotFound(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	require.NoError(t, db.Create(&models.Media{Title: "Live", Type: models.MediaTypeVideo, FilePath: "/l.mkv"}).Error)

	// Восстановление живой строки — 404-логика, а не молчаливый 200.
	assert.ErrorIs(t, store.RestoreMedia(ctx, 1), ErrNotInTrash)
}

func TestMediaStore_PurgeRemovesMetadata(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	m := &models.Media{
		Title: "M", Type: models.MediaTypeVideo, FilePath: "/m.mkv",
		Metadata: &models.Metadata{Title: "Meta"},
	}
	require.NoError(t, db.Create(m).Error)
	require.NoError(t, store.Delete(ctx, m.ID))
	require.NoError(t, store.PurgeMedia(ctx, m.ID))

	var left int64
	require.NoError(t, db.Model(&models.Metadata{}).Count(&left).Error)
	assert.Zero(t, left, "metadata-сироты после purge нет")
}
