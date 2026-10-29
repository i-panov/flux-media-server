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

	progress, total, err := store.FindByUser(ctx, 1, "", 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(1), total)
	require.Len(t, progress, 1)
	require.NotNil(t, progress[0].Media, "Media must be preloaded")
	assert.Equal(t, "Movie", progress[0].Media.Title)
	assert.Equal(t, 42, progress[0].Position)
}

// Блок «Продолжить прослушивание» не должен вытесняться более свежими
// записями видео: тип фильтруется в запросе, а не на клиенте.
func TestProgressStore_FindByUserFiltersByMediaType(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	video := &models.Media{Title: "Movie", Type: models.MediaTypeVideo, FilePath: "/movie.mkv"}
	audio := &models.Media{Title: "Song", Type: models.MediaTypeAudio, FilePath: "/song.mp3"}
	require.NoError(t, db.Create(video).Error)
	require.NoError(t, db.Create(audio).Error)

	store := NewProgressRepository(db)
	ctx := context.Background()
	require.NoError(t, store.Upsert(ctx, &models.WatchProgress{
		UserID: 1, MediaID: video.ID, Position: 10, Duration: 100,
	}))
	require.NoError(t, store.Upsert(ctx, &models.WatchProgress{
		UserID: 1, MediaID: audio.ID, Position: 20, Duration: 200,
	}))

	progress, total, err := store.FindByUser(ctx, 1, models.MediaTypeAudio, 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(1), total)
	require.Len(t, progress, 1)
	assert.Equal(t, audio.ID, progress[0].MediaID)

	all, allTotal, err := store.FindByUser(ctx, 1, "", 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(2), allTotal)
	assert.Len(t, all, 2)
}
