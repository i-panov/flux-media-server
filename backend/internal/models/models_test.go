package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// newTestDB открывает in-memory SQLite с включёнными FK и ограничивает
// пул одним соединением, чтобы :memory: не разъехалась между коннектами.
func newTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open("file::memory:?cache=shared&_foreign_keys=on"), &gorm.Config{})
	require.NoError(t, err)
	sqlDB, err := db.DB()
	require.NoError(t, err)
	sqlDB.SetMaxOpenConns(1)
	t.Cleanup(func() { sqlDB.Close() })
	return db
}

// migrateAll повторяет схему из repository.AutoMigrate, чтобы тесты
// проверяли ту же самую миграцию, что и продакшн.
func migrateAll(t *testing.T, db *gorm.DB) {
	t.Helper()
	db.SetupJoinTable(&Media{}, "Artists", &MediaArtist{})
	require.NoError(t, db.AutoMigrate(
		&Media{},
		&Metadata{},
		&User{},
		&WatchProgress{},
		&Favorite{},
		&Collection{},
		&CollectionItem{},
		&Lyrics{},
		&RefreshToken{},
		&Artist{},
	))
}

// tableSQL возвращает SQL-определение таблицы из sqlite_master.
func tableSQL(t *testing.T, db *gorm.DB, table string) string {
	t.Helper()
	var sql string
	require.NoError(t, db.Raw(
		"SELECT sql FROM sqlite_master WHERE type='table' AND name=?", table,
	).Scan(&sql).Error)
	return sql
}

func indexExists(t *testing.T, db *gorm.DB, name string) bool {
	t.Helper()
	var count int64
	require.NoError(t, db.Raw(
		"SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name=?", name,
	).Scan(&count).Error)
	return count > 0
}

// TestSchemaMigrateAndCheckConstraints проверяет, что AutoMigrate проходит
// и создаёт CHECK-ограничение favorites и ожидаемые индексы.
func TestSchemaMigrateAndCheckConstraints(t *testing.T) {
	db := newTestDB(t)
	migrateAll(t, db)

	// CHECK «ровно один из media_id/artist_id» создаётся на fresh-БД.
	sql := tableSQL(t, db, "favorites")
	assert.Contains(t, sql, "CHECK")

	// Композитный индекс (user_id, updated_at) для списка «недавно
	// просмотренных» создан.
	assert.True(t, indexExists(t, db, "idx_progress_user_updated"), "composite progress index missing")
	// Индекс на expires_at для DeleteExpired создан.
	assert.True(t, indexExists(t, db, "idx_refresh_tokens_expires_at"), "refresh token expires_at index missing")
	// Избыточный uniqueIndex поверх составного PK media_artists удалён.
	assert.False(t, indexExists(t, db, "idx_media_artist_pair"), "redundant idx_media_artist_pair must not be created")
}

// TestUniqueConstraints проверяет, что дубликаты отклоняются уникальными
// индексами, а не только бизнес-логикой.
func TestUniqueConstraints(t *testing.T) {
	db := newTestDB(t)
	migrateAll(t, db)

	require.NoError(t, db.Create(&User{Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&Media{Title: "M1"}).Error)
	require.NoError(t, db.Create(&Artist{Name: "Artist A"}).Error)
	require.NoError(t, db.Create(&Collection{UserID: 1, Name: "C1"}).Error)

	t.Run("duplicate artist name", func(t *testing.T) {
		err := db.Create(&Artist{Name: "Artist A"}).Error
		assert.Error(t, err, "duplicate artist name must be rejected")
	})

	t.Run("duplicate media_artist pair", func(t *testing.T) {
		require.NoError(t, db.Create(&MediaArtist{MediaID: 1, ArtistID: 1, Position: 0}).Error)
		err := db.Create(&MediaArtist{MediaID: 1, ArtistID: 1, Position: 1}).Error
		assert.Error(t, err, "duplicate (media_id, artist_id) must be rejected by composite PK")
	})

	t.Run("duplicate collection position", func(t *testing.T) {
		require.NoError(t, db.Create(&CollectionItem{CollectionID: 1, MediaID: 1, Position: 1}).Error)
		err := db.Create(&CollectionItem{CollectionID: 1, MediaID: 2, Position: 1}).Error
		assert.Error(t, err, "duplicate (collection_id, position) must be rejected")
	})

	t.Run("duplicate collection media", func(t *testing.T) {
		err := db.Create(&CollectionItem{CollectionID: 1, MediaID: 1, Position: 2}).Error
		assert.Error(t, err, "duplicate (collection_id, media_id) must be rejected")
	})

	t.Run("duplicate favorite media", func(t *testing.T) {
		mediaID := uint(1)
		require.NoError(t, db.Create(&Favorite{UserID: 1, MediaID: &mediaID}).Error)
		err := db.Create(&Favorite{UserID: 1, MediaID: &mediaID}).Error
		assert.Error(t, err, "duplicate (user_id, media_id) favorite must be rejected")
	})

	t.Run("duplicate watch progress", func(t *testing.T) {
		require.NoError(t, db.Create(&WatchProgress{UserID: 1, MediaID: 1, Position: 10}).Error)
		err := db.Create(&WatchProgress{UserID: 1, MediaID: 1, Position: 20}).Error
		assert.Error(t, err, "duplicate (user_id, media_id) progress must be rejected")
	})
}

// TestFavoriteCheckConstraint проверяет CHECK «ровно один из MediaID/ArtistID».
func TestFavoriteCheckConstraint(t *testing.T) {
	db := newTestDB(t)
	migrateAll(t, db)

	require.NoError(t, db.Create(&User{Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&Media{Title: "M1"}).Error)
	require.NoError(t, db.Create(&Artist{Name: "Artist A"}).Error)

	mediaID := uint(1)
	artistID := uint(1)

	t.Run("both set rejected", func(t *testing.T) {
		err := db.Create(&Favorite{UserID: 1, MediaID: &mediaID, ArtistID: &artistID}).Error
		assert.Error(t, err, "favorite with both media and artist must be rejected")
	})

	t.Run("both nil rejected", func(t *testing.T) {
		err := db.Create(&Favorite{UserID: 1}).Error
		assert.Error(t, err, "favorite without target must be rejected")
	})

	t.Run("media only accepted", func(t *testing.T) {
		err := db.Create(&Favorite{UserID: 1, MediaID: &mediaID}).Error
		assert.NoError(t, err)
	})

	t.Run("artist only accepted", func(t *testing.T) {
		err := db.Create(&Favorite{UserID: 1, ArtistID: &artistID}).Error
		assert.NoError(t, err)
	})
}

// TestMediaTypeScan проверяет нормализацию регистра и пробелов в Scan.
func TestMediaTypeScan(t *testing.T) {
	var mt MediaType
	require.NoError(t, mt.Scan(" Video "))
	assert.Equal(t, MediaTypeVideo, mt)

	require.NoError(t, mt.Scan("AUDIO"))
	assert.Equal(t, MediaTypeAudio, mt)

	// nil не меняет текущее значение.
	require.NoError(t, mt.Scan(nil))
	assert.Equal(t, MediaTypeAudio, mt)

	var zero MediaType
	require.Error(t, zero.Scan(42))
}
