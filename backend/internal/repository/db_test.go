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
		Type:     models.MediaTypeAudio,
		FilePath: "/audio/track.mp3",
	}
	require.NoError(t, store.Create(ctx, media))

	// Insert join rows with explicit positions.
	require.NoError(t, db.Exec("INSERT INTO media_artists (media_id, artist_id, position) VALUES (?, ?, 0), (?, ?, 1)",
		media.ID, a2.ID, media.ID, a1.ID).Error)

	// FindAll must succeed (no "no such column: media_artists.position").
	list, _, err := store.FindAll(ctx, map[string]interface{}{"type": string(models.MediaTypeAudio)}, 10, 0)
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

// Regression test: an artist linked to multiple media must NOT be
// duplicated when preloading. The old GORM many2many Preload with a
// manual JOIN media_artists caused a cartesian product — each artist
// appeared once per media_artists row across ALL media, not just the
// current one.
func TestMediaStore_ArtistsNotDuplicatedAcrossMedia(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	shared, err := NewArtistRepository(db).FindOrCreateByName(ctx, "Shared Artist")
	require.NoError(t, err)
	other, err := NewArtistRepository(db).FindOrCreateByName(ctx, "Other Artist")
	require.NoError(t, err)

	m1 := &models.Media{Title: "Track1", Type: models.MediaTypeAudio, FilePath: "/a/1.mp3"}
	require.NoError(t, store.Create(ctx, m1))
	m2 := &models.Media{Title: "Track2", Type: models.MediaTypeAudio, FilePath: "/a/2.mp3"}
	require.NoError(t, store.Create(ctx, m2))

	// m1: Shared (pos 0) + Other (pos 1); m2: Shared (pos 0).
	require.NoError(t, db.Exec(
		"INSERT INTO media_artists (media_id, artist_id, position) VALUES (?,?,0),(?,?,1),(?,?,0)",
		m1.ID, shared.ID, m1.ID, other.ID, m2.ID, shared.ID,
	).Error)

	list, _, err := store.FindAll(ctx, nil, 10, 0)
	require.NoError(t, err)
	require.Len(t, list, 2)

	// m1 must have exactly 2 artists (not 3).
	require.Len(t, list[0].Artists, 2, "m1 should have 2 artists, not duplicated")
	assert.Equal(t, "Shared Artist", list[0].Artists[0].Name)
	assert.Equal(t, "Other Artist", list[0].Artists[1].Name)

	// m2 must have exactly 1 artist (not 2).
	require.Len(t, list[1].Artists, 1, "m2 should have 1 artist, not duplicated")
	assert.Equal(t, "Shared Artist", list[1].Artists[0].Name)

	// FindByID must also be correct.
	got, err := store.FindByID(ctx, m1.ID)
	require.NoError(t, err)
	require.Len(t, got.Artists, 2)
}
