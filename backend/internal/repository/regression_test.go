package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Regression test: the old unique index on artist_name alone made every
// SECOND media favorite fail with a UNIQUE constraint error (all media
// favorites had artist_name=”).
func TestFavoriteStore_MultipleMediaFavorites(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	// Create user and media records so FK constraints are satisfied.
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.User{ID: 2, Email: "u2@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "Test1"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 11, Title: "Test2"}).Error)

	store := NewFavoriteRepository(db)
	ctx := context.Background()

	m1, m2 := uint(10), uint(11)
	require.NoError(t, store.Create(ctx, &models.Favorite{UserID: 1, MediaID: &m1}))
	require.NoError(t, store.Create(ctx, &models.Favorite{UserID: 1, MediaID: &m2}),
		"second media favorite of the same user must succeed")

	// Duplicate favorite must still be rejected by the unique index.
	err = store.Create(ctx, &models.Favorite{UserID: 1, MediaID: &m1})
	assert.Error(t, err, "duplicate favorite must fail")

	// Another user can favorite the same media.
	require.NoError(t, store.Create(ctx, &models.Favorite{UserID: 2, MediaID: &m1}))

	// Artist favorites of different users don't collide.
	artistStore := NewArtistRepository(db)
	a, err := artistStore.FindOrCreateByName(ctx, "Pink Floyd")
	require.NoError(t, err)
	require.NoError(t, store.Create(ctx, &models.Favorite{UserID: 1, ArtistID: &a.ID}))
	require.NoError(t, store.Create(ctx, &models.Favorite{UserID: 2, ArtistID: &a.ID}))
}

// Regression test: watch progress must have a composite unique index on
// (user_id, media_id) — the old broken tag syntax never created it.
func TestProgressStore_UpsertNoDuplicates(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	// Create user and media so FK constraints are satisfied.
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "Test"}).Error)

	// Direct duplicate insert must fail on the unique index.
	p1 := &models.WatchProgress{UserID: 1, MediaID: 10, Position: 5}
	require.NoError(t, db.Create(p1).Error)

	p2 := &models.WatchProgress{UserID: 1, MediaID: 10, Position: 7}
	err = db.Create(p2).Error
	assert.Error(t, err, "duplicate (user_id, media_id) progress must be rejected by unique index")
}

// Regression test: collection items must have a composite unique index on
// (collection_id, media_id).
func TestCollectionItemStore_NoDuplicates(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	// Create referenced records for FK constraints.
	require.NoError(t, db.Create(&models.Collection{ID: 1}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "Test"}).Error)

	store := NewCollectionItemRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Add(ctx, &models.CollectionItem{CollectionID: 1, MediaID: 10}))
	err = store.Add(ctx, &models.CollectionItem{CollectionID: 1, MediaID: 10})
	assert.Error(t, err, "duplicate collection item must be rejected by unique index")
}

// Regression test: metadata external_id must NOT be unique — manual metadata
// updates create rows with empty external IDs and must not collide.
func TestMetadata_EmptyExternalIDNoCollision(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	require.NoError(t, db.Create(&models.Metadata{Title: "a"}).Error)
	require.NoError(t, db.Create(&models.Metadata{Title: "b"}).Error,
		"second metadata row with empty external_id must succeed")
}

// Migrations must be idempotent and safe on a fresh database.
func TestRunMigrationsOnFreshDB(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, RunMigrations(db))
	require.NoError(t, AutoMigrate(db))
	// Running again after AutoMigrate must also work.
	require.NoError(t, RunMigrations(db))
}
