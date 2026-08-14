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

	// Create user and media first so FK constraints are satisfied.
	// Create user and media first so FK constraints are satisfied.
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	mediaID := uint(10)
	require.NoError(t, db.Create(&models.Media{ID: mediaID, Title: "Test"}).Error)

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	fav := &models.Favorite{
		UserID:  1,
		MediaID: &mediaID,
	}
	require.NoError(t, store.Create(ctx, fav))

	favs, total, err := store.FindByUser(ctx, 1, "", 50, 0)
	assert.NoError(t, err)
	assert.Len(t, favs, 1)
	assert.Equal(t, int64(1), total)
}

func TestFavoriteStore_FindByUserAndMedia(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	mediaID := uint(10)
	require.NoError(t, db.Create(&models.Media{ID: mediaID, Title: "Test"}).Error)

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
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

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	mediaID := uint(10)
	require.NoError(t, db.Create(&models.Media{ID: mediaID, Title: "Test"}).Error)

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
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

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	mediaID := uint(10)
	require.NoError(t, db.Create(&models.Media{ID: mediaID, Title: "Test"}).Error)

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:  1,
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

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)

	store := NewFavoriteRepository(db)
	artistStore := NewArtistRepository(db)
	ctx := context.Background()

	artist, err := artistStore.FindOrCreateByName(ctx, "Pink Floyd")
	require.NoError(t, err)
	require.NotNil(t, artist)

	require.NoError(t, store.Create(ctx, &models.Favorite{
		UserID:   1,
		ArtistID: &artist.ID,
	}))

	found, err := store.FindByUserAndArtist(ctx, 1, artist.ID)
	assert.NoError(t, err)
	assert.NotNil(t, found)

	isFav, err := store.IsArtistFavorited(ctx, 1, artist.ID)
	assert.NoError(t, err)
	assert.True(t, isFav)

	require.NoError(t, store.DeleteArtist(ctx, 1, artist.ID))

	isFav, err = store.IsArtistFavorited(ctx, 1, artist.ID)
	assert.NoError(t, err)
	assert.False(t, isFav)
}
