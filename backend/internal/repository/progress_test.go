package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Regression test (MAJOR): FindByUser («продолжить просмотр») должен
// подгружать объект Media — иначе у клиента N+1 запросов.
func TestProgressStore_FindByUserPreloadsMedia(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{ID: 10, Title: "Movie", Type: models.MediaTypeVideo}).Error)

	store := NewProgressRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Upsert(ctx, &models.WatchProgress{
		UserID: 1, MediaID: 10, Position: 42, Duration: 100,
	}))

	progress, total, err := store.FindByUser(ctx, 1, 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(1), total)
	require.Len(t, progress, 1)
	require.NotNil(t, progress[0].Media, "Media must be preloaded")
	assert.Equal(t, "Movie", progress[0].Media.Title)
	assert.Equal(t, 42, progress[0].Position)
}
