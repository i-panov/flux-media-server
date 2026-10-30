package repository

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

// Дедуп артистов без учёта регистра: «Кино»/«кино»/« КИНО » — один артист.
// До name_norm (бинарное сравнение в SQLite) каждый вариант плодил строку.
func TestArtistStore_FindOrCreateCaseInsensitive(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewArtistRepository(db)
	ctx := context.Background()

	first, err := store.FindOrCreateByName(ctx, "Кино")
	require.NoError(t, err)
	second, err := store.FindOrCreateByName(ctx, "кино")
	require.NoError(t, err)
	third, err := store.FindOrCreateByName(ctx, " КИНО ")
	require.NoError(t, err)

	assert.Equal(t, first.ID, second.ID)
	assert.Equal(t, first.ID, third.ID)
	// Отображаемое имя — первый увиденный вариант.
	assert.Equal(t, "Кино", first.Name)

	var count int64
	require.NoError(t, db.Model(&models.Artist{}).Count(&count).Error)
	assert.Equal(t, int64(1), count)
}

func TestResolveArtists_CaseInsensitive(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	resolved, err := resolveArtists(db, []models.Artist{
		{Name: "Kino"},
		{Name: "kino"},
	})
	require.NoError(t, err)
	require.Len(t, resolved, 2)
	assert.Equal(t, resolved[0].ID, resolved[1].ID)
}

func TestArtistStore_UpdateConflictsAcrossCase(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	store := NewArtistRepository(db)
	ctx := context.Background()

	a, err := store.FindOrCreateByName(ctx, "Кино")
	require.NoError(t, err)
	_, err = store.FindOrCreateByName(ctx, "Музыка")
	require.NoError(t, err)

	_, err = store.Update(ctx, a.ID, "музыка")
	require.ErrorIs(t, err, ErrArtistNameTaken)
}

// normalizeArtistNames сливает существующие дубли в минимальный id
// и перевешивает связи media_artists и favorites.
func TestNormalizeArtistNames_MergesDuplicates(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	ctx := context.Background()

	// Сажаем дубли в обход кода (с индексом их не вставить).
	require.NoError(t, db.Exec("DROP INDEX IF EXISTS idx_artists_name_norm").Error)
	require.NoError(t, db.Exec(`INSERT INTO artists (name, name_norm, created_at, updated_at)
		VALUES ('Кино', 'кино', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
		       ('КИНО', 'кино', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`).Error)

	mediaStore := NewMediaRepository(db)
	require.NoError(t, mediaStore.Create(ctx, &models.Media{
		Title:    "Трек",
		Type:     models.MediaTypeAudio,
		FilePath: "/t.mp3",
		Artists:  []models.Artist{{Name: "Кино"}},
	}))

	var keeper models.Artist
	require.NoError(t, db.Where("name = ?", "Кино").First(&keeper).Error)
	var dupe models.Artist
	require.NoError(t, db.Where("name = ?", "КИНО").First(&dupe).Error)

	// Медиа ссылается на дубль напрямую + избранное на дубль.
	require.NoError(t, db.Exec(
		`INSERT INTO media_artists (media_id, artist_id, position) VALUES (1, ?, 1)`,
		dupe.ID).Error)
	require.NoError(t, db.Exec(
		`INSERT INTO users (email, created_at, updated_at)
		 VALUES ('u@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`).Error)
	require.NoError(t, db.Exec(
		`INSERT INTO favorites (user_id, artist_id, created_at) VALUES (1, ?, CURRENT_TIMESTAMP)`,
		dupe.ID).Error)

	require.NoError(t, db.Transaction(func(tx *gorm.DB) error {
		return normalizeArtistNames(tx)
	}))

	var count int64
	require.NoError(t, db.Model(&models.Artist{}).Count(&count).Error)
	assert.Equal(t, int64(1), count)

	var remaining models.Artist
	require.NoError(t, db.First(&remaining).Error)
	assert.Equal(t, keeper.ID, remaining.ID)
	assert.Equal(t, "кино", remaining.NameNorm)

	var links int64
	require.NoError(t, db.Table("media_artists").
		Where("media_id = ?", 1).Count(&links).Error)
	assert.Equal(t, int64(1), links)

	var favArtist uint
	require.NoError(t, db.Table("favorites").Where("user_id = ?", 1).
		Pluck("artist_id", &favArtist).Error)
	assert.Equal(t, keeper.ID, favArtist)

	// Повтор идемпотентен.
	require.NoError(t, db.Transaction(func(tx *gorm.DB) error {
		return normalizeArtistNames(tx)
	}))
	require.NoError(t, db.Model(&models.Artist{}).Count(&count).Error)
	assert.Equal(t, int64(1), count)
}
