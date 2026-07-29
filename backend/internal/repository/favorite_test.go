package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestFavoriteStore_CreateAndFindByUser(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	fav := &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}
	require.NoError(t, store.Create(ctx, fav))

	favs, err := store.FindByUser(ctx, 1, "video")
	assert.NoError(t, err)
	assert.Len(t, favs, 1)
	assert.Equal(t, "video", favs[0].Type)
}

func TestFavoriteStore_FindByUserAndMedia(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	found, err := store.FindByUserAndMedia(ctx, 1, 10)
	assert.NoError(t, err)
	assert.NotNil(t, found)
	assert.Equal(t, uint(1), found.UserID)
}

func TestFavoriteStore_IsFavorited(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	isFav, err := store.IsFavorited(ctx, 1, 10)
	assert.NoError(t, err)
	assert.True(t, isFav)

	isFav, err = store.IsFavorited(ctx, 1, 99)
	assert.NoError(t, err)
	assert.False(t, isFav)
}

func TestFavoriteStore_Delete(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	mediaID := uint(10)
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
		Type:    "video",
		MediaID: &mediaID,
	}))

	require.NoError(t, store.Delete(ctx, 1, 10))

	isFav, err := store.IsFavorited(ctx, 1, 10)
	assert.NoError(t, err)
	assert.False(t, isFav)
}

func TestFavoriteStore_ArtistFavorite(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	artist := "Pink Floyd"
	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:     1,
		Type:       "artist",
		ArtistName: &artist,
	}))

	found, err := store.FindByUserAndArtist(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.NotNil(t, found)

	isFav, err := store.IsArtistFavorited(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.True(t, isFav)

	require.NoError(t, store.DeleteArtist(ctx, 1, "Pink Floyd"))

	isFav, err = store.IsArtistFavorited(ctx, 1, "Pink Floyd")
	assert.NoError(t, err)
	assert.False(t, isFav)
}
