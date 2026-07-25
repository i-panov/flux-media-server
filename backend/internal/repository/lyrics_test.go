package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestLyricsStore_UpsertAndFind(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	lyrics := &models.Lyrics{
		MediaID:     1,
		LyricsText:  "La la la",
		Translation: "Ля ля ля",
		SyncData:    `[{"t":0,"text":"La la la"}]`,
		Source:      "id3",
	}
	require.NoError(t, store.Upsert(ctx, lyrics))

	found, err := store.FindByMediaID(ctx, 1)
	assert.NoError(t, err)
	assert.NotNil(t, found)
	assert.Equal(t, "La la la", found.LyricsText)
	assert.Equal(t, "Ля ля ля", found.Translation)
}

func TestLyricsStore_UpsertReplaces(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "Original",
		Source:     "id3",
	}))
	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "Updated",
		Source:     "manual",
	}))

	found, err := store.FindByMediaID(ctx, 1)
	assert.NoError(t, err)
	assert.Equal(t, "Updated", found.LyricsText)
}

func TestLyricsStore_Delete(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Upsert(ctx, &models.Lyrics{
		MediaID:    1,
		LyricsText: "La la la",
	}))

	require.NoError(t, store.Delete(ctx, 1))

	_, err = store.FindByMediaID(ctx, 1)
	assert.Error(t, err)
}

func TestLyricsStore_FindNotFound(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewLyricsRepository(db)
	ctx := context.Background()

	_, err = store.FindByMediaID(ctx, 999)
	assert.Error(t, err)
}
