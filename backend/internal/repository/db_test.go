package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestInitDB(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)
	assert.NotNil(t, db)

	// Verify the connection is usable
	sqlDB, err := db.DB()
	require.NoError(t, err)
	assert.NoError(t, sqlDB.Ping())
}

func TestAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)

	err = AutoMigrate(db)
	assert.NoError(t, err)

	// Verify tables were created
	var tables []string
	err = db.Raw("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").Scan(&tables).Error
	assert.NoError(t, err)

	tableSet := make(map[string]bool)
	for _, t := range tables {
		tableSet[t] = true
	}

	assert.True(t, tableSet["media"])
	assert.True(t, tableSet["metadata"])
	assert.True(t, tableSet["users"])
	assert.True(t, tableSet["watch_progresses"])
	assert.True(t, tableSet["favorites"])
	assert.True(t, tableSet["collections"])
	assert.True(t, tableSet["collection_items"])
	assert.True(t, tableSet["lyrics"])
	assert.True(t, tableSet["artists"])
	assert.True(t, tableSet["media_artists"])
}

// Regression test: the media_artists JOIN in the Artists preload must not
// reference columns outside the query scope (GORM generates the preload as a
// separate SELECT; adding ORDER BY on the join table without a JOIN fails).
func TestMediaStore_PreloadArtistsWithJoinOrder(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	a1, err := NewArtistRepository(db).FindOrCreateByName(ctx, "Artist A")
	require.NoError(t, err)
	a2, err := NewArtistRepository(db).FindOrCreateByName(ctx, "Artist B")
	require.NoError(t, err)

	media := &models.Media{
		Title:    "Track",
		Type:     "audio",
		FilePath: "/audio/track.mp3",
	}
	require.NoError(t, store.Create(ctx, media))

	// Insert join rows with explicit positions.
	require.NoError(t, db.Exec("INSERT INTO media_artists (media_id, artist_id, position) VALUES (?, ?, 0), (?, ?, 1)",
		media.ID, a2.ID, media.ID, a1.ID).Error)

	// FindAll must succeed (no "no such column: media_artists.position").
	list, _, err := store.FindAll(ctx, map[string]interface{}{"type": "audio"}, 10, 0)
	require.NoError(t, err)
	require.Len(t, list, 1)
	require.Len(t, list[0].Artists, 2, "both artists must be loaded")
	// Position 0 = Artist B, position 1 = Artist A.
	assert.Equal(t, "Artist B", list[0].Artists[0].Name, "first artist must be position 0")
	assert.Equal(t, "Artist A", list[0].Artists[1].Name, "second artist must be position 1")

	// FindByID must also succeed.
	got, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, got.Artists, 2)
	assert.Equal(t, "Artist B", got.Artists[0].Name)
}
