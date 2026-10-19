package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Разовая заливка размеров кадра при старте сервера ищет видео с
// width = 0. Фильтр должен быть узким: аудио и уже заполненные видео в
// выборку не попадают, порядок — по ID (проход доходит до конца).
func TestMediaStore_FindVideosMissingDimensions(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	// Видео без размеров — кандидат на заливку.
	noDims := &models.Media{
		Title: "Old Video", Filename: "old.mp4",
		Type: models.MediaTypeVideo, FilePath: "/media/old.mp4",
	}
	// Видео, у которого размеры уже есть, — трогать нельзя.
	withDims := &models.Media{
		Title: "New Video", Filename: "new.mp4",
		Type: models.MediaTypeVideo, FilePath: "/media/new.mp4",
		Width: 1920, Height: 1080,
	}
	// Аудио: ширина/высота не имеют смысла, заполнять нечего.
	audio := &models.Media{
		Title: "Track", Filename: "track.mp3",
		Type: models.MediaTypeAudio, FilePath: "/media/track.mp3",
	}
	// В корзине: клиенту не показывается, проходить по ней незачем.
	trashed := &models.Media{
		Title: "Trashed", Filename: "trashed.mp4",
		Type: models.MediaTypeVideo, FilePath: "/media/trashed.mp4",
	}
	for _, m := range []*models.Media{noDims, withDims, audio, trashed} {
		require.NoError(t, store.Create(ctx, m))
	}
	require.NoError(t, store.Delete(ctx, trashed.ID))

	found, err := store.FindVideosMissingDimensions(ctx, 10)
	require.NoError(t, err)
	require.Len(t, found, 1)
	assert.Equal(t, noDims.ID, found[0].ID)
	assert.Zero(t, found[0].Width)
	assert.Zero(t, found[0].Height)
}

// UpdateDimensions пишет ТОЛЬКО размеры и не трогает связи артистов:
// заливка идёт по записям, прочитанным без Preload, и общий Update на
// такой записи стирал бы артистов.
func TestMediaStore_UpdateDimensionsKeepsArtists(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{
		Title: "With Artist", Type: models.MediaTypeVideo, FilePath: "/a.mkv",
		Artists: []models.Artist{{Name: "Someone"}},
	}
	require.NoError(t, store.Create(ctx, media))

	require.NoError(t, store.UpdateDimensions(ctx, media.ID, 1920, 1080))

	after, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	assert.Equal(t, 1920, after.Width)
	assert.Equal(t, 1080, after.Height)
	require.Len(t, after.Artists, 1, "артист потерян при записи размеров")
	assert.Equal(t, "Someone", after.Artists[0].Name)
}

// UpdateDimensions не затирает остальные поля записи.
func TestMediaStore_UpdateDimensionsKeepsOtherFields(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{
		Title: "Original", Type: models.MediaTypeVideo, FilePath: "/a.mkv",
		Duration: 120, Description: "keep me",
	}
	require.NoError(t, store.Create(ctx, media))

	require.NoError(t, store.UpdateDimensions(ctx, media.ID, 640, 480))

	after, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	assert.Equal(t, "Original", after.Title)
	assert.Equal(t, 120, after.Duration)
	assert.Equal(t, "keep me", after.Description)
}

// Успешно заполненные размеры перестают быть кандидатами: проход не
// должен крутиться по кругу на одном и том же наборе ID.
func TestMediaStore_FindVideosMissingDimensionsSkipsFilled(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{
		Title: "Fill Me", Filename: "fill.mkv",
		Type: models.MediaTypeVideo, FilePath: "/media/fill.mkv",
	}
	require.NoError(t, store.Create(ctx, media))

	found, err := store.FindVideosMissingDimensions(ctx, 10)
	require.NoError(t, err)
	require.Len(t, found, 1)

	media.Width = 1280
	media.Height = 720
	require.NoError(t, store.Update(ctx, media))

	found, err = store.FindVideosMissingDimensions(ctx, 10)
	require.NoError(t, err)
	assert.Empty(t, found)
}

// Запись с заполненной шириной, но пустой высотой — тоже кандидат:
// клиенту нужна ПАРА размеров, и при фильтре «только width = 0» такая
// запись не заполнилась бы никогда.
func TestMediaStore_FindVideosMissingDimensionsCatchesHalfFilled(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	half := &models.Media{
		Title: "Half", Type: models.MediaTypeVideo, FilePath: "/half.mkv",
		Width: 1920, Height: 0,
	}
	require.NoError(t, store.Create(ctx, half))

	found, err := store.FindVideosMissingDimensions(ctx, 10)
	require.NoError(t, err)
	require.Len(t, found, 1)
	assert.Equal(t, half.ID, found[0].ID)
}

// Лимит выборки: бэкфилл идёт порциями, чтобы отмена по контексту не
// держала в памяти всю библиотеку.
func TestMediaStore_FindVideosMissingDimensionsRespectsLimit(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	for i := 0; i < 3; i++ {
		require.NoError(t, store.Create(ctx, &models.Media{
			Title: "V", Filename: "v.mp4",
			Type: models.MediaTypeVideo, FilePath: "/media/v.mp4",
		}))
	}

	found, err := store.FindVideosMissingDimensions(ctx, 2)
	require.NoError(t, err)
	assert.Len(t, found, 2)
}
