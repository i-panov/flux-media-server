package repository

import (
	"fmt"
	"log"

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
	sqlDB.SetMaxOpenConns(1)

	return db, nil
}

func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.MediaLibrary{},
		&models.Favorite{},
		&models.Collection{},
		&models.CollectionItem{},
		&models.Lyrics{},
		&models.RefreshToken{},
	)
}

// RunMigrations applies schema fixes that AutoMigrate cannot perform
// (dropping/replacing wrong indexes, deduplicating data). Must run BEFORE
// AutoMigrate so that the correct indexes can be created afterwards.
func RunMigrations(db *gorm.DB) error {
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
	}

	return nil
}

// tableExists reports whether a table exists in the SQLite database.
func tableExists(db *gorm.DB, table string) bool {
	var count int64
	db.Raw("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&count)
	return count > 0
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
