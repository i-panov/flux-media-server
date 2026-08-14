package repository

import (
	"fmt"
	"log"
	"runtime"

	"flux/internal/models"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// InitDB opens the SQLite database. In debug mode all SQL statements are
// logged (including parameter values!); otherwise only warnings/errors are.
func InitDB(path string, debug ...bool) (*gorm.DB, error) {
	logMode := logger.Warn
	if len(debug) > 0 && debug[0] {
		logMode = logger.Info
	}

	// DSN parameters ensure PRAGMAs are applied to EVERY connection in the
	// pool, not just the first one (db.Exec only affects one connection).
	db, err := gorm.Open(sqlite.Open(path+"?_journal=WAL&_busy_timeout=5000&_foreign_keys=on&_synchronous=NORMAL&_cache_size=-8000&_temp_store=MEMORY&_mmap_size=268435456"), &gorm.Config{
		Logger: logger.Default.LogMode(logMode),
	})
	if err != nil {
		return nil, err
	}

	// SQLite allows only one concurrent writer. Limiting the pool avoids
	// SQLITE_BUSY errors under concurrent writes.
	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}
	maxConns := runtime.NumCPU()
	if maxConns < 4 {
		maxConns = 4
	}
	sqlDB.SetMaxOpenConns(maxConns)

	// Enable foreign keys — required for SQLite FK constraints.
	db.Exec("PRAGMA foreign_keys = ON")

	// Performance tuning for SQLite in server mode.
	db.Exec("PRAGMA journal_mode = WAL")
	db.Exec("PRAGMA synchronous = NORMAL")
	db.Exec("PRAGMA cache_size = -8000")
	db.Exec("PRAGMA busy_timeout = 5000")
	db.Exec("PRAGMA temp_store = MEMORY")
	db.Exec("PRAGMA mmap_size = 268435456")

	return db, nil
}

func AutoMigrate(db *gorm.DB) error {
	db.SetupJoinTable(&models.Media{}, "Artists", &models.MediaArtist{})
	return db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.Favorite{},
		&models.Collection{},
		&models.CollectionItem{},
		&models.Lyrics{},
		&models.RefreshToken{},
		&models.Artist{},
	)
}

// RunMigrations applies schema fixes that AutoMigrate cannot perform
// (dropping/replacing wrong indexes, deduplicating data, dropping columns/tables).
// Must run BEFORE AutoMigrate so that the correct indexes can be created afterwards.
func RunMigrations(db *gorm.DB) error {
	// --- Phase 1: fix indexes and dedupe (from earlier migrations) ---

	// favorites: the old unique index on artist_name alone made every second
	// media-like fail ('' collided globally). Drop it and normalize '' to
	// NULL so the new composite (user_id, artist_name) index works.
	if err := dropUniqueIndexesOnColumn(db, "favorites", "artist_name"); err != nil {
		return fmt.Errorf("migrate favorites indexes: %w", err)
	}
	if tableExists(db, "favorites") && columnExists(db, "favorites", "artist_name") {
		if err := db.Exec("UPDATE favorites SET artist_name = NULL WHERE artist_name = ''").Error; err != nil {
			return fmt.Errorf("migrate favorites data: %w", err)
		}
	}

	// metadatas: unique external_id broke manual metadata updates (empty
	// external IDs collided after the first row).
	if err := dropUniqueIndexesOnColumn(db, "metadatas", "external_id"); err != nil {
		return fmt.Errorf("migrate metadatas indexes: %w", err)
	}

	// watch_progresses / collection_items: composite unique indexes were
	// never created due to a broken tag syntax, so duplicates may exist.
	// Remove them (keeping the newest row) before the unique index is added.
	if tableExists(db, "watch_progresses") {
		if err := db.Exec(`DELETE FROM watch_progresses WHERE id NOT IN (
			SELECT MAX(id) FROM watch_progresses GROUP BY user_id, media_id)`).Error; err != nil {
			return fmt.Errorf("dedupe watch_progresses: %w", err)
		}
	}
	if tableExists(db, "collection_items") {
		if err := db.Exec(`DELETE FROM collection_items WHERE id NOT IN (
			SELECT MAX(id) FROM collection_items GROUP BY collection_id, media_id)`).Error; err != nil {
			return fmt.Errorf("dedupe collection_items: %w", err)
		}
		// Deduplicate by (collection_id, position) before adding the unique
		// index idx_collection_position. Keep the newest row per position.
		if err := db.Exec(`DELETE FROM collection_items WHERE id NOT IN (
			SELECT MAX(id) FROM collection_items GROUP BY collection_id, position)`).Error; err != nil {
			return fmt.Errorf("dedupe collection_items by position: %w", err)
		}
	}

	// --- Phase 2: drop redundant columns and tables ---

	// media: drop library_id (FK to media_libraries, no longer needed).
	if err := dropColumnIfExists(db, "media", "library_id"); err != nil {
		return fmt.Errorf("drop media.library_id: %w", err)
	}

	// Примечание: watch_progresses.duration и completed больше НЕ удаляются —
	// эти поля теперь часть модели WatchProgress (клиент присылает их в
	// UpdateProgress) и пересоздаются AutoMigrate.

	// favorites: drop type (redundant — media type is in the media table;
	// artist favorites are identified by artist_name IS NOT NULL).
	if err := dropColumnIfExists(db, "favorites", "type"); err != nil {
		return fmt.Errorf("drop favorites.type: %w", err)
	}

	// media_libraries: drop the entire table (replaced by config paths).
	if tableExists(db, "media_libraries") {
		log.Printf("migration: dropping table media_libraries")
		if err := db.Exec("DROP TABLE IF EXISTS media_libraries").Error; err != nil {
			return fmt.Errorf("drop media_libraries: %w", err)
		}
	}

	// --- Phase 3: extract artists from media.artist into the artists table ---

	// Only needed while the legacy media.artist column still exists.
	if columnExists(db, "media", "artist") {
		if !tableExists(db, "artists") {
			log.Printf("migration: creating artists table")
			if err := db.Exec(`CREATE TABLE IF NOT EXISTS artists (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				name TEXT NOT NULL UNIQUE,
				created_at DATETIME,
				updated_at DATETIME
			)`).Error; err != nil {
				return fmt.Errorf("create artists: %w", err)
			}
		}
		if !tableExists(db, "media_artists") {
			log.Printf("migration: creating media_artists table")
			if err := db.Exec(`CREATE TABLE IF NOT EXISTS media_artists (
				media_id INTEGER NOT NULL,
				artist_id INTEGER NOT NULL,
				position INTEGER DEFAULT 0,
				PRIMARY KEY (media_id, artist_id)
			)`).Error; err != nil {
				return fmt.Errorf("create media_artists: %w", err)
			}
		}

		// 1. Collect distinct non-empty artist names from media.
		if err := db.Exec(`INSERT OR IGNORE INTO artists (name, created_at, updated_at)
			SELECT DISTINCT TRIM(artist), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
			FROM media WHERE artist IS NOT NULL AND TRIM(artist) <> ''`).Error; err != nil {
			return fmt.Errorf("migrate artists from media: %w", err)
		}

		// 2. Collect distinct artist names from favorites (may not exist in media).
		if columnExists(db, "favorites", "artist_name") {
			if err := db.Exec(`INSERT OR IGNORE INTO artists (name, created_at, updated_at)
				SELECT DISTINCT TRIM(artist_name), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
				FROM favorites WHERE artist_name IS NOT NULL AND TRIM(artist_name) <> ''`).Error; err != nil {
				return fmt.Errorf("migrate artists from favorites: %w", err)
			}
		}

		// 3. Link media to artists.
		if err := db.Exec(`INSERT OR IGNORE INTO media_artists (media_id, artist_id, position)
			SELECT m.id, a.id, 0
			FROM media m JOIN artists a ON TRIM(m.artist) = a.name
			WHERE m.artist IS NOT NULL AND TRIM(m.artist) <> ''`).Error; err != nil {
			return fmt.Errorf("link media_artists: %w", err)
		}

		// 4. Re-point favorites from artist_name to artist_id.
		if columnExists(db, "favorites", "artist_name") && !columnExists(db, "favorites", "artist_id") {
			if err := db.Exec("ALTER TABLE favorites ADD COLUMN artist_id INTEGER").Error; err != nil {
				return fmt.Errorf("add favorites.artist_id: %w", err)
			}
			if err := db.Exec(`UPDATE favorites SET artist_id = (
				SELECT id FROM artists WHERE name = favorites.artist_name
			) WHERE artist_name IS NOT NULL AND TRIM(artist_name) <> ''`).Error; err != nil {
				return fmt.Errorf("migrate favorites.artist_id: %w", err)
			}
			if err := dropColumnIfExists(db, "favorites", "artist_name"); err != nil {
				return fmt.Errorf("drop favorites.artist_name: %w", err)
			}
		}

		// 5. Drop the legacy media.artist column.
		if err := dropColumnIfExists(db, "media", "artist"); err != nil {
			return fmt.Errorf("drop media.artist: %w", err)
		}
	}

	return nil
}

// tableExists reports whether a table exists in the SQLite database.
func tableExists(db *gorm.DB, table string) bool {
	var count int64
	db.Raw("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&count)
	return count > 0
}

// columnExists reports whether a column exists in the given table.
func columnExists(db *gorm.DB, table, column string) bool {
	var count int64
	db.Raw("SELECT COUNT(*) FROM pragma_table_info(?) WHERE name=?", table, column).Scan(&count)
	return count > 0
}

// dropColumnIfExists drops a column from a table if it exists.
// First drops any indexes that reference the column (SQLite does not do
// this automatically with ALTER TABLE DROP COLUMN).
// Uses ALTER TABLE DROP COLUMN (SQLite >= 3.35.0).
func dropColumnIfExists(db *gorm.DB, table, column string) error {
	if !columnExists(db, table, column) {
		return nil
	}

	// Drop all indexes that include this column.
	if err := dropIndexesOnColumn(db, table, column); err != nil {
		return fmt.Errorf("drop indexes on %s.%s: %w", table, column, err)
	}

	log.Printf("migration: dropping column %s.%s", table, column)
	return db.Exec("ALTER TABLE " + table + " DROP COLUMN " + column).Error
}

// dropIndexesOnColumn drops every index (unique or not) on table that
// includes the given column.
func dropIndexesOnColumn(db *gorm.DB, table, column string) error {
	var indexes []struct {
		Name   string
		Unique bool `gorm:"column:unique"`
	}
	if err := db.Raw("PRAGMA index_list(" + table + ")").Scan(&indexes).Error; err != nil {
		return err
	}

	for _, idx := range indexes {
		var cols []struct {
			Name string
		}
		if err := db.Raw("PRAGMA index_info(" + idx.Name + ")").Scan(&cols).Error; err != nil {
			return err
		}
		for _, c := range cols {
			if c.Name == column {
				log.Printf("migration: dropping index %s on %s (references %s)", idx.Name, table, column)
				if err := db.Exec("DROP INDEX IF EXISTS " + idx.Name).Error; err != nil {
					return err
				}
				break
			}
		}
	}
	return nil
}

// dropUniqueIndexesOnColumn drops every unique index on table whose only
// column is column. Used to replace wrongly defined unique indexes.
func dropUniqueIndexesOnColumn(db *gorm.DB, table, column string) error {
	var indexes []struct {
		Name   string
		Unique bool `gorm:"column:unique"`
	}
	if err := db.Raw("PRAGMA index_list(" + table + ")").Scan(&indexes).Error; err != nil {
		return err
	}

	for _, idx := range indexes {
		if !idx.Unique {
			continue
		}
		var cols []struct {
			Name string
		}
		if err := db.Raw("PRAGMA index_info(" + idx.Name + ")").Scan(&cols).Error; err != nil {
			return err
		}
		if len(cols) == 1 && cols[0].Name == column {
			log.Printf("migration: dropping wrong unique index %s on %s(%s)", idx.Name, table, column)
			if err := db.Exec("DROP INDEX IF EXISTS " + idx.Name).Error; err != nil {
				return err
			}
		}
	}
	return nil
}
