package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Regression test (CRITICAL): Update должен обновлять только переданные
// непустые поля. Старый Save(media) записывал ВСЕ колонки включая нулевые,
// поэтому частично заполненный Media (например, из FindByHash) затирал
// Description/Genre/Duration/Year.
func TestMediaStore_UpdatePartialFields(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{
		Title:        "Full Title",
		Filename:     "full.mkv",
		Year:         2001,
		Description:  "Full description",
		Type:         models.MediaTypeVideo,
		Album:        "Album",
		Genre:        "Genre",
		Duration:     100,
		FilePath:     "/media/full.mkv",
		FileSize:     1024,
		FileHash:     "abc",
		QuickHash:    "q1",
		ThumbnailURL: "/api/media/1/thumb",
		CoverURL:     "/api/media/1/cover",
	}
	require.NoError(t, store.Create(ctx, media))

	// Частичное обновление: только Title.
	require.NoError(t, store.Update(ctx, &models.Media{ID: media.ID, Title: "Renamed"}))

	got, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	assert.Equal(t, "Renamed", got.Title)
	assert.Equal(t, "Full description", got.Description, "description must not be wiped")
	assert.Equal(t, 2001, got.Year, "year must not be wiped")
	assert.Equal(t, 100, got.Duration, "duration must not be wiped")
	assert.Equal(t, "Album", got.Album)
	assert.Equal(t, "Genre", got.Genre)
	assert.Equal(t, models.MediaTypeVideo, got.Type)
	assert.Equal(t, "/media/full.mkv", got.FilePath)
	assert.Equal(t, int64(1024), got.FileSize)
	assert.Equal(t, "abc", got.FileHash)
	assert.Equal(t, "/api/media/1/thumb", got.ThumbnailURL)
	assert.Equal(t, "/api/media/1/cover", got.CoverURL)
}

// Regression test (CRITICAL): пустые имена артистов не должны попадать в
// Replace — иначе создаётся артист с пустым именем, а второй раз —
// UNIQUE-ошибка.
func TestMediaStore_UpdateEmptyArtistNames(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{Title: "Track", Type: models.MediaTypeAudio, FilePath: "/a.mp3"}
	require.NoError(t, store.Create(ctx, media))

	// Пустые и пробельные имена + один реальный.
	media.Artists = []models.Artist{{Name: ""}, {Name: "   "}, {Name: "Real Artist"}}
	require.NoError(t, store.Update(ctx, media))

	var artists []models.Artist
	require.NoError(t, db.Find(&artists).Error)
	require.Len(t, artists, 1, "only the real artist must be created")
	assert.Equal(t, "Real Artist", artists[0].Name)

	// Повторный Update снова с пустым именем не должен упасть на UNIQUE.
	media.Artists = []models.Artist{{Name: ""}, {Name: "Real Artist"}}
	require.NoError(t, store.Update(ctx, media))

	var links int64
	require.NoError(t, db.Model(&models.MediaArtist{}).Count(&links).Error)
	assert.Equal(t, int64(1), links)

	got, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	require.Len(t, got.Artists, 1)
	assert.Equal(t, "Real Artist", got.Artists[0].Name)
}

// Regression test: сбой Create артиста не из-за UNIQUE не маскируется
// fallback-поиском «существующего по имени».
func TestMediaStore_UpdateArtistRealDBErrorNotMasked(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{Title: "Track", Type: models.MediaTypeAudio, FilePath: "/a.mp3"}
	require.NoError(t, store.Create(ctx, media))

	// Ломаем таблицу artists: Create артиста теперь падает с реальной ошибкой,
	// и она должна быть возвращена, а не маскирована.
	require.NoError(t, db.Exec("DROP TABLE media_artists").Error)
	require.NoError(t, db.Exec("DROP TABLE artists").Error)

	media.Artists = []models.Artist{{Name: "New Artist"}}
	err = store.Update(ctx, media)
	assert.Error(t, err, "real DB failure must be propagated")
	assert.NotContains(t, err.Error(), "record not found")
}

// FindByPathBasic должен быть одним дешёвым SELECT без Preload.
func TestMediaStore_FindByPathBasic(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, &models.Media{
		Title:    "Track",
		Type:     models.MediaTypeAudio,
		FilePath: "/media/track.mp3",
	}))

	got, err := store.FindByPathBasic(ctx, "/media/track.mp3")
	require.NoError(t, err)
	assert.Equal(t, "Track", got.Title)
	assert.Nil(t, got.Metadata, "no preload in the basic lookup")

	_, err = store.FindByPathBasic(ctx, "/media/missing.mp3")
	assert.Error(t, err)
}

// Regression test (MAJOR): ошибка LoadArtistsForMedia не должна проглатываться.
func TestMediaStore_LoadArtistsErrorPropagated(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	artistRepo := NewArtistRepository(db)
	ctx := context.Background()

	artist, err := artistRepo.FindOrCreateByName(ctx, "Artist A")
	require.NoError(t, err)
	media := &models.Media{Title: "Track", Type: models.MediaTypeAudio, FilePath: "/a.mp3"}
	require.NoError(t, store.Create(ctx, media))
	require.NoError(t, db.Exec("INSERT INTO media_artists (media_id, artist_id) VALUES (?, ?)", media.ID, artist.ID).Error)

	// Убираем таблицу медиаторов — загрузка артистов теперь падает.
	require.NoError(t, db.Exec("DROP TABLE media_artists").Error)

	_, err = store.FindByID(ctx, media.ID)
	assert.Error(t, err, "FindByID must propagate LoadArtistsForMedia error")

	_, err = store.FindByPath(ctx, "/a.mp3")
	assert.Error(t, err, "FindByPath must propagate LoadArtistsForMedia error")
}

// Regression test (MINOR): % и _ в поисковом запросе должны искаться
// посимвольно, а не трактоваться как LIKE-шаблон.
func TestMediaStore_FindAllLikeEscaping(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	for _, title := range []string{"50% Off", "50X Off", "a_b", "axb"} {
		require.NoError(t, store.Create(ctx, &models.Media{Title: title, Type: models.MediaTypeVideo}))
	}

	// q = "50%": без экранирования '%' — шаблон, нашлось бы и "50X Off".
	list, total, err := store.FindAll(ctx, map[string]interface{}{"q": "50%"}, 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(1), total, "%% must be literal")
	require.Len(t, list, 1)
	assert.Equal(t, "50% Off", list[0].Title)

	// q = "a_b": без экранирования '_' — шаблон, нашлось бы и "axb".
	list, total, err = store.FindAll(ctx, map[string]interface{}{"q": "a_b"}, 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(1), total, "_ must be literal")
	require.Len(t, list, 1)
	assert.Equal(t, "a_b", list[0].Title)

	// Обычный поиск не сломан.
	_, total, err = store.FindAll(ctx, map[string]interface{}{"q": "Off"}, 10, 0)
	require.NoError(t, err)
	assert.Equal(t, int64(2), total)
}

// Update с Metadata должен сохранять ассоциацию (upsert) и проставлять
// metadata_id — контракт сохранён от старого Save(media).
func TestMediaStore_UpdateMetadataAssociation(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	ctx := context.Background()

	media := &models.Media{Title: "Movie", Type: models.MediaTypeVideo, FilePath: "/m.mkv"}
	require.NoError(t, store.Create(ctx, media))

	media.Metadata = &models.Metadata{Title: "Poster", PosterURL: "/p.jpg", Rating: 8.5}
	require.NoError(t, store.Update(ctx, media))

	got, err := store.FindByID(ctx, media.ID)
	require.NoError(t, err)
	require.NotNil(t, got.Metadata, "metadata association must be saved")
	assert.Equal(t, "Poster", got.Metadata.Title)
	assert.Equal(t, "/p.jpg", got.Metadata.PosterURL)
	assert.Equal(t, 8.5, got.Metadata.Rating)
	require.NotNil(t, got.MetadataID)
	assert.Equal(t, got.Metadata.ID, *got.MetadataID)
}

// Delete должен каскадно удалять и ссылки media_artists (без FK в старых БД).
func TestMediaStore_DeleteCascadesArtistLinks(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewMediaRepository(db)
	artistRepo := NewArtistRepository(db)
	ctx := context.Background()

	artist, err := artistRepo.FindOrCreateByName(ctx, "Artist A")
	require.NoError(t, err)
	media := &models.Media{Title: "Track", Type: models.MediaTypeAudio, FilePath: "/a.mp3"}
	require.NoError(t, store.Create(ctx, media))
	require.NoError(t, db.Exec("INSERT INTO media_artists (media_id, artist_id) VALUES (?, ?)", media.ID, artist.ID).Error)

	require.NoError(t, store.Delete(ctx, media.ID))

	var links int64
	require.NoError(t, db.Model(&models.MediaArtist{}).Where("media_id = ?", media.ID).Count(&links).Error)
	assert.Equal(t, int64(0), links, "media_artists rows must be deleted with the media")
}
