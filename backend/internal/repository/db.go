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

	db, err := gorm.Open(sqlite.Open(path+"?_journal=WAL&_busy_timeout=5000"), &gorm.Config{
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
	if tableExists(db, "favorites") {
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

	// watch_progresses: drop duration (duplicates media.duration) and completed
	// (can be derived from position vs duration).
	if err := dropColumnIfExists(db, "watch_progresses", "duration"); err != nil {
		return fmt.Errorf("drop watch_progresses.duration: %w", err)
	}
	if err := dropColumnIfExists(db, "watch_progresses", "completed"); err != nil {
		return fmt.Errorf("drop watch_progresses.completed: %w", err)
	}

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
