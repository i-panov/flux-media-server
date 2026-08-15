package repository

import (
	"errors"
	"fmt"
	"log"
	"runtime"
	"strings"

	"flux/internal/models"

	"github.com/mattn/go-sqlite3"
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
	// _txlock=immediate makes every BEGIN a BEGIN IMMEDIATE: SQLite write
	// transactions are serialized at BEGIN instead of failing with
	// SQLITE_BUSY_SNAPSHOT mid-transaction (read-then-write races in WAL).
	db, err := gorm.Open(sqlite.Open(path+"?_journal=WAL&_busy_timeout=5000&_foreign_keys=on&_synchronous=NORMAL&_cache_size=-8000&_temp_store=MEMORY&_mmap_size=268435456&_txlock=immediate"), &gorm.Config{
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
//
// Вся миграция выполняется в одной транзакции: DDL в SQLite транзакционно,
// поэтому обрыв на середине откатывается целиком, а не оставляет частично
// мигрированную БД (guard-функции tableExists/columnExists работают на tx).
func RunMigrations(db *gorm.DB) error {
	return db.Transaction(func(tx *gorm.DB) error {
		// --- Phase 1: fix indexes and dedupe (from earlier migrations) ---

		// favorites: the old unique index on artist_name alone made every second
		// media-like fail ('' collided globally). Drop it and normalize '' to
		// NULL so the new composite (user_id, artist_name) index works.
		if err := dropUniqueIndexesOnColumn(tx, "favorites", "artist_name"); err != nil {
			return fmt.Errorf("migrate favorites indexes: %w", err)
		}
		hasFavArtistName, err := tableHasColumn(tx, "favorites", "artist_name")
		if err != nil {
			return fmt.Errorf("check favorites.artist_name: %w", err)
		}
		if hasFavArtistName {
			if err := tx.Exec("UPDATE favorites SET artist_name = NULL WHERE artist_name = ''").Error; err != nil {
				return fmt.Errorf("migrate favorites data: %w", err)
			}
		}

		// metadatas: unique external_id broke manual metadata updates (empty
		// external IDs collided after the first row).
		if err := dropUniqueIndexesOnColumn(tx, "metadatas", "external_id"); err != nil {
			return fmt.Errorf("migrate metadatas indexes: %w", err)
		}

		// watch_progresses / collection_items: composite unique indexes were
		// never created due to a broken tag syntax, so duplicates may exist.
		// Remove them (keeping the newest row) before the unique index is added.
		if ok, err := tableExists(tx, "watch_progresses"); err != nil {
			return fmt.Errorf("check watch_progresses: %w", err)
		} else if ok {
			if err := tx.Exec(`DELETE FROM watch_progresses WHERE id NOT IN (
				SELECT MAX(id) FROM watch_progresses GROUP BY user_id, media_id)`).Error; err != nil {
				return fmt.Errorf("dedupe watch_progresses: %w", err)
			}
		}
		if ok, err := tableExists(tx, "collection_items"); err != nil {
			return fmt.Errorf("check collection_items: %w", err)
		} else if ok {
			if err := tx.Exec(`DELETE FROM collection_items WHERE id NOT IN (
				SELECT MAX(id) FROM collection_items GROUP BY collection_id, media_id)`).Error; err != nil {
				return fmt.Errorf("dedupe collection_items: %w", err)
			}
			// Deduplicate by (collection_id, position) before adding the unique
			// index idx_collection_position. Keep the newest row per position.
			if err := tx.Exec(`DELETE FROM collection_items WHERE id NOT IN (
				SELECT MAX(id) FROM collection_items GROUP BY collection_id, position)`).Error; err != nil {
				return fmt.Errorf("dedupe collection_items by position: %w", err)
			}
		}

		// --- Phase 2: drop redundant columns and tables ---

		// media: drop library_id (FK to media_libraries, no longer needed).
		if err := dropColumnIfExists(tx, "media", "library_id"); err != nil {
			return fmt.Errorf("drop media.library_id: %w", err)
		}

		// Примечание: watch_progresses.duration и completed больше НЕ удаляются —
		// эти поля теперь часть модели WatchProgress (клиент присылает их в
		// UpdateProgress) и пересоздаются AutoMigrate.

		// favorites: drop type (redundant — media type is in the media table;
		// artist favorites are identified by artist_name IS NOT NULL).
		if err := dropColumnIfExists(tx, "favorites", "type"); err != nil {
			return fmt.Errorf("drop favorites.type: %w", err)
		}

		// media_libraries: drop the entire table (replaced by config paths).
		if ok, err := tableExists(tx, "media_libraries"); err != nil {
			return fmt.Errorf("check media_libraries: %w", err)
		} else if ok {
			log.Printf("migration: dropping table media_libraries")
			if err := tx.Exec("DROP TABLE IF EXISTS media_libraries").Error; err != nil {
				return fmt.Errorf("drop media_libraries: %w", err)
			}
		}

		// --- Phase 3: extract artists from media.artist into the artists table ---

		// Only needed while the legacy media.artist column still exists.
		hasLegacyArtist, err := tableHasColumn(tx, "media", "artist")
		if err != nil {
			return fmt.Errorf("check media.artist: %w", err)
		}
		if hasLegacyArtist {
			if ok, err := tableExists(tx, "artists"); err != nil {
				return fmt.Errorf("check artists: %w", err)
			} else if !ok {
				log.Printf("migration: creating artists table")
				if err := tx.Exec(`CREATE TABLE IF NOT EXISTS artists (
					id INTEGER PRIMARY KEY AUTOINCREMENT,
					name TEXT NOT NULL UNIQUE,
					created_at DATETIME,
					updated_at DATETIME
				)`).Error; err != nil {
					return fmt.Errorf("create artists: %w", err)
				}
			}
			if ok, err := tableExists(tx, "media_artists"); err != nil {
				return fmt.Errorf("check media_artists: %w", err)
			} else if !ok {
				log.Printf("migration: creating media_artists table")
				if err := tx.Exec(`CREATE TABLE IF NOT EXISTS media_artists (
					media_id INTEGER NOT NULL,
					artist_id INTEGER NOT NULL,
					position INTEGER DEFAULT 0,
					PRIMARY KEY (media_id, artist_id)
				)`).Error; err != nil {
					return fmt.Errorf("create media_artists: %w", err)
				}
			}

			// 1. Collect distinct non-empty artist names from media.
			if err := tx.Exec(`INSERT OR IGNORE INTO artists (name, created_at, updated_at)
				SELECT DISTINCT TRIM(artist), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
				FROM media WHERE artist IS NOT NULL AND TRIM(artist) <> ''`).Error; err != nil {
				return fmt.Errorf("migrate artists from media: %w", err)
			}

			// 2. Collect distinct artist names from favorites (may not exist in media).
			if ok, err := tableHasColumn(tx, "favorites", "artist_name"); err != nil {
				return fmt.Errorf("check favorites.artist_name: %w", err)
			} else if ok {
				if err := tx.Exec(`INSERT OR IGNORE INTO artists (name, created_at, updated_at)
					SELECT DISTINCT TRIM(artist_name), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
					FROM favorites WHERE artist_name IS NOT NULL AND TRIM(artist_name) <> ''`).Error; err != nil {
					return fmt.Errorf("migrate artists from favorites: %w", err)
				}
			}

			// 3. Link media to artists.
			if err := tx.Exec(`INSERT OR IGNORE INTO media_artists (media_id, artist_id, position)
				SELECT m.id, a.id, 0
				FROM media m JOIN artists a ON TRIM(m.artist) = a.name
				WHERE m.artist IS NOT NULL AND TRIM(m.artist) <> ''`).Error; err != nil {
				return fmt.Errorf("link media_artists: %w", err)
			}

			// 4. Re-point favorites from artist_name to artist_id.
			hasFavArtistName, err = tableHasColumn(tx, "favorites", "artist_name")
			if err != nil {
				return fmt.Errorf("check favorites.artist_name: %w", err)
			}
			hasFavArtistID, err := tableHasColumn(tx, "favorites", "artist_id")
			if err != nil {
				return fmt.Errorf("check favorites.artist_id: %w", err)
			}
			if hasFavArtistName && !hasFavArtistID {
				if err := tx.Exec("ALTER TABLE favorites ADD COLUMN artist_id INTEGER").Error; err != nil {
					return fmt.Errorf("add favorites.artist_id: %w", err)
				}
				if err := tx.Exec(`UPDATE favorites SET artist_id = (
					SELECT id FROM artists WHERE name = favorites.artist_name
				) WHERE artist_name IS NOT NULL AND TRIM(artist_name) <> ''`).Error; err != nil {
					return fmt.Errorf("migrate favorites.artist_id: %w", err)
				}
				if err := dropColumnIfExists(tx, "favorites", "artist_name"); err != nil {
					return fmt.Errorf("drop favorites.artist_name: %w", err)
				}
			}

			// 5. Drop the legacy media.artist column.
			if err := dropColumnIfExists(tx, "media", "artist"); err != nil {
				return fmt.Errorf("drop media.artist: %w", err)
			}
		}

		return nil
	})
}

// tableExists reports whether a table exists in the SQLite database.
func tableExists(db *gorm.DB, table string) (bool, error) {
	var count int64
	if err := db.Raw("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

// columnExists reports whether a column exists in the given table.
func columnExists(db *gorm.DB, table, column string) (bool, error) {
	var count int64
	if err := db.Raw("SELECT COUNT(*) FROM pragma_table_info(?) WHERE name=?", table, column).Scan(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

// tableHasColumn reports whether the table exists and has the given column.
func tableHasColumn(db *gorm.DB, table, column string) (bool, error) {
	ok, err := tableExists(db, table)
	if err != nil || !ok {
		return false, err
	}
	return columnExists(db, table, column)
}

// isUniqueViolation reports whether err is a SQLite UNIQUE/PRIMARY KEY
// constraint violation. Extended code 2067 (SQLITE_CONSTRAINT_UNIQUE); for
// drivers that only report the primary code, falls back to the message text.
func isUniqueViolation(err error) bool {
	var sqliteErr sqlite3.Error
	if errors.As(err, &sqliteErr) {
		if sqliteErr.ExtendedCode == sqlite3.ErrConstraintUnique ||
			sqliteErr.ExtendedCode == sqlite3.ErrConstraintPrimaryKey {
			return true
		}
		if sqliteErr.Code == sqlite3.ErrConstraint {
			return strings.Contains(strings.ToLower(sqliteErr.Error()), "unique")
		}
	}
	return false
}

// cascadeDelete удаляет зависимые строки по ключу column = value в
// переданной транзакции. Используется вместо ручных каскадов в
// Delete-методах MediaStore/UserStore/CollectionStore.
func cascadeDelete(tx *gorm.DB, column string, value interface{}, tables ...interface{}) error {
	for _, t := range tables {
		if err := tx.Where(column+" = ?", value).Delete(t).Error; err != nil {
			return err
		}
	}
	return nil
}

// dropColumnIfExists drops a column from a table if it exists.
// First drops any indexes that reference the column (SQLite does not do
// this automatically with ALTER TABLE DROP COLUMN).
// Uses ALTER TABLE DROP COLUMN (SQLite >= 3.35.0).
func dropColumnIfExists(db *gorm.DB, table, column string) error {
	exists, err := columnExists(db, table, column)
	if err != nil {
		return err
	}
	if !exists {
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
