package repository

import (
	"database/sql"
	"errors"
	"fmt"
	"log"
	"runtime"
	"strings"
	"sync"
	"time"

	"flux/internal/models"

	"github.com/mattn/go-sqlite3"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// fluxDriverName — имя зарегистрированного sql-драйвера с ConnectHook,
// применяющим PRAGMA, которые НЕ поддержаны DSN-ключами mattn/go-sqlite3
// (см. parseDSNParams в драйвере): temp_store и mmap_size.
const fluxDriverName = "flux_sqlite3"

// registerFluxDriverOnce защищает sql.Register от повторной регистрации
// (InitDB зовётся многократно — тесты, консольный режим).
var registerFluxDriverOnce sync.Once

// registerFluxDriver регистрирует драйвер с хуком: PRAGMA temp_store и
// mmap_size выполняются на КАЖДОМ новом соединении пула (db.Exec в InitDB
// затронул бы только один коннект).
func registerFluxDriver() {
	registerFluxDriverOnce.Do(func() {
		sql.Register(fluxDriverName, &sqlite3.SQLiteDriver{
			ConnectHook: func(conn *sqlite3.SQLiteConn) error {
				if _, err := conn.Exec("PRAGMA temp_store = MEMORY;", nil); err != nil {
					return err
				}
				_, err := conn.Exec("PRAGMA mmap_size = 268435456;", nil)
				return err
			},
		})
	})
}

// InitDB opens the SQLite database. In debug mode all SQL statements are
// logged (including parameter values!); otherwise only warnings/errors are.
func InitDB(path string, debug ...bool) (*gorm.DB, error) {
	logMode := logger.Warn
	if len(debug) > 0 && debug[0] {
		logMode = logger.Info
	}

	// DSN-параметры обеспечивают PRAGMAs на EVERY connection in the pool,
	// not just the first one (db.Exec only affects one connection).
	// Поддержанные драйвером ключи (см. parseDSNParams): _journal, _busy_timeout,
	// _foreign_keys, _synchronous, _cache_size, _txlock. temp_store и mmap_size
	// драйвером НЕ поддержаны — применяются через ConnectHook (см. выше).
	// _txlock=immediate makes every BEGIN a BEGIN IMMEDIATE: SQLite write
	// transactions are serialized at BEGIN instead of failing with
	// SQLITE_BUSY_SNAPSHOT mid-transaction (read-then-write races in WAL).
	registerFluxDriver()
	db, err := gorm.Open(sqlite.New(sqlite.Config{
		DriverName: fluxDriverName,
		DSN:        path + "?_journal=WAL&_busy_timeout=5000&_foreign_keys=on&_synchronous=NORMAL&_cache_size=-8000&_txlock=immediate",
	}), &gorm.Config{
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

	// In-memory SQLite не разделяется между соединениями: каждое новое
	// соединение пула получает СВОЮ пустую базу (ни файла, ни общего
	// кеша). С пулом в одно соединение все обращения видят одну базу.
	// Без этого любая фоновая задача (бэкфилл размеров кадра при старте
	// сервера) на тестовой БД получала «no such table: …» и ломала
	// соседние тесты.
	if isMemoryPath(path) {
		sqlDB.SetMaxOpenConns(1)
		sqlDB.SetMaxIdleConns(1)
		return db, nil
	}

	maxConns := runtime.NumCPU()
	if maxConns < 4 {
		maxConns = 4
	}
	sqlDB.SetMaxOpenConns(maxConns)

	return db, nil
}

// isMemoryPath — признак БД в памяти, у которой каждое соединение пула
// получает отдельную копию данных.
func isMemoryPath(path string) bool {
	return strings.Contains(path, ":memory:") ||
		strings.Contains(path, "mode=memory")
}

// guardLegacyCatalogSchema не даёт AutoMigrate молча пересобрать
// seasons/work_items со старыми именами FK (fk_works_seasons,
// fk_seasons_items, fk_works_items): DROP TABLE с foreign_keys=on
// каскадно удаляет эпизоды. Лучше отказать в старте и потребовать backup.
func guardLegacyCatalogSchema(db *gorm.DB) error {
	var rows []struct {
		Name string
		SQL  string
	}
	if err := db.Raw(`SELECT name, sql FROM sqlite_master
		WHERE type = 'table' AND name IN ('seasons','work_items','franchise_entries')`).
		Scan(&rows).Error; err != nil {
		return fmt.Errorf("check catalog schema: %w", err)
	}
	for _, row := range rows {
		if name := legacyCatalogFK(row.SQL); name != "" {
			return fmt.Errorf(
				"найдена устаревшая FK-связь каталога %q в таблице %s. Запуск остановлен, "+
					"чтобы не потерять work_items. Сделайте backup БД и пересоздайте seasons/work_items "+
					"с актуальными FK (fk_seasons_work, fk_work_items_work, fk_work_items_season)", name, row.Name)
		}
	}
	return nil
}

func legacyCatalogFK(ddl string) string {
	legacy := []string{"fk_works_seasons", "fk_works_items", "fk_seasons_items"}
	for _, name := range legacy {
		if strings.Contains(ddl, name) {
			return name
		}
	}
	return ""
}

func AutoMigrate(db *gorm.DB) error {
	if err := guardLegacyCatalogSchema(db); err != nil {
		return err
	}
	if err := db.SetupJoinTable(&models.Media{}, "Artists", &models.MediaArtist{}); err != nil {
		return err
	}
	if err := db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.Favorite{},
		&models.Collection{},
		&models.CollectionItem{},
		&models.Lyrics{},
		&models.RefreshToken{},
		&models.DeviceAuth{},
		&models.Artist{},
		&models.TranscodeTask{},
		&models.ExtractTask{},
		&models.UploadTask{},
		&models.Subtitle{},
		&models.SchemaMigration{},
		&models.Setting{},
		&models.Work{},
		&models.Season{},
		&models.WorkItem{},
		&models.Franchise{},
		&models.FranchiseEntry{},
		&models.Tag{},
		&models.MediaTag{},
		&models.WorkTag{},
		&models.FranchiseTag{},
	); err != nil {
		return err
	}
	if err := createCatalogIndexes(db); err != nil {
		return err
	}
	if err := createMetadataIndexes(db); err != nil {
		return err
	}
	if err := seedSystemTags(db); err != nil {
		return err
	}
	if err := createVideoKindTriggers(db); err != nil {
		return err
	}
	if err := createMediaSourceTriggers(db); err != nil {
		return err
	}
	return nil
}

// createVideoKindTriggers проверяет media.video_kind без пересборки media.
// CHECK через AutoMigrate на existing-БД вызывал recreateTable с DROP TABLE
// и каскадно сносил favorites/progress/subtitles и остальные дочерние строки.
func createVideoKindTriggers(db *gorm.DB) error {
	condition := `(
		(NEW.type = 'video' AND (NEW.video_kind IS NULL OR NEW.video_kind NOT IN ('movie','episode')))
		OR (NEW.type IS NOT NULL AND NEW.type <> 'video' AND NEW.video_kind IS NOT NULL)
		OR (NEW.type IS NULL AND NEW.video_kind IS NOT NULL)
	)`
	queries := []string{
		`DROP TRIGGER IF EXISTS media_video_kind_insert`,
		`CREATE TRIGGER media_video_kind_insert BEFORE INSERT ON media
		FOR EACH ROW WHEN ` + condition + `
		BEGIN SELECT RAISE(ABORT, 'media_video_kind'); END`,
		`DROP TRIGGER IF EXISTS media_video_kind_update`,
		`CREATE TRIGGER media_video_kind_update
		BEFORE UPDATE OF type, video_kind ON media
		FOR EACH ROW WHEN (NEW.type IS NOT OLD.type OR NEW.video_kind IS NOT OLD.video_kind)
			AND ` + condition + `
		BEGIN SELECT RAISE(ABORT, 'media_video_kind'); END`,
	}
	return db.Transaction(func(tx *gorm.DB) error {
		for _, query := range queries {
			if err := tx.Exec(query).Error; err != nil {
				return fmt.Errorf("create media_video_kind trigger: %w", err)
			}
		}
		return nil
	})
}

// createCatalogIndexes добавляет частичные UNIQUE-индексы, которые GORM
// не умеет выразить тегами. Обычные position-индексы создаёт AutoMigrate.
func createCatalogIndexes(db *gorm.DB) error {
	indexes := []string{
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_work_items_work_media
			ON work_items(work_id, media_id) WHERE work_id IS NOT NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_work_items_season_media
			ON work_items(season_id, media_id) WHERE season_id IS NOT NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_franchise_entries_work
			ON franchise_entries(franchise_id, work_id) WHERE work_id IS NOT NULL`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_franchise_entries_media
			ON franchise_entries(franchise_id, media_id) WHERE media_id IS NOT NULL`,
	}
	for _, query := range indexes {
		if err := db.Exec(query).Error; err != nil {
			return fmt.Errorf("create catalog index: %w", err)
		}
	}
	return nil
}

func seedSystemTags(db *gorm.DB) error {
	for _, row := range []struct{ slug, name string }{
		{"film", "Фильм"},
		{"clip", "Клип"},
		{"podcast", "Подкаст"},
	} {
		if err := db.Exec(`INSERT OR IGNORE INTO tags
			(tag_group, slug, name, created_at, updated_at)
			VALUES ('format', ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
			row.slug, row.name).Error; err != nil {
			return fmt.Errorf("seed tag %s: %w", row.slug, err)
		}
	}
	return nil
}

// createMetadataIndexes — partial unique, которые нельзя вешать до
// AutoMigrate на свежей БД: таблиц ещё нет.
func createMetadataIndexes(db *gorm.DB) error {
	indexes := []string{
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_metadata_source_external
			ON metadata(source, external_id) WHERE COALESCE(external_id, '') <> ''`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_media_metadata
			ON media(metadata_id) WHERE metadata_id IS NOT NULL`,
	}
	for _, query := range indexes {
		if err := db.Exec(query).Error; err != nil {
			return fmt.Errorf("create metadata index: %w", err)
		}
	}
	return nil
}

// RunMigrations applies schema fixes that AutoMigrate cannot perform
// (dropping/replacing wrong indexes, deduplicating data, dropping columns/tables).
// Must run BEFORE AutoMigrate so that the correct indexes can be created afterwards.
//
// Каждая версия миграции выполняется в своей транзакции: DDL в SQLite
// транзакционно, обрыв внутри версии откатывается целиком. Обрыв между
// версиями безопасен: следующая версия продолжит с записанной schema_migrations.
func RunMigrations(db *gorm.DB) error {
	if err := guardLegacyCatalogSchema(db); err != nil {
		return err
	}
	if err := runMigrationsV1(db); err != nil {
		return err
	}
	if err := runMigrationsV2(db); err != nil {
		return err
	}
	if err := runMigrationsV3(db); err != nil {
		return err
	}
	if err := runMigrationsV4(db); err != nil {
		return err
	}
	if err := runMigrationsV5(db); err != nil {
		return err
	}
	if err := runMigrationsV6(db); err != nil {
		return err
	}
	if err := runMigrationsV7(db); err != nil {
		return err
	}
	if err := runMigrationsV8(db); err != nil {
		return err
	}
	return runMigrationsV9(db)
}

// runMigrationsV1 — историческая миграция схемы. Оставлена отдельной,
// чтобы новая v2 не перезапускала неидемпотентные шаги на уже обновлённой БД.
func runMigrationsV1(db *gorm.DB) error {
	const schemaVersion = 1
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version: %w", err)
		}
		if applied > 0 {
			return nil
		}
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

		// media: старый unique-индекс на file_path (снят из модели в пользу
		// обычного — unique конфликтовал с soft-delete: файл после
		// удаления записи уже не импортировался, сканер сыпал UNIQUE
		// constraint failed на каждом старте). AutoMigrate старые индексы
		// не дропает, чистим здесь — дальше создастся обычный.
		if err := dropUniqueIndexesOnColumn(tx, "media", "file_path"); err != nil {
			return fmt.Errorf("migrate media indexes: %w", err)
		}

		// metadata: unique external_id broke manual metadata updates (empty
		// external IDs collided after the first row). Таблица называется
		// metadata, не metadatas — старое имя было no-op.
		if err := dropUniqueIndexesOnColumn(tx, "metadata", "external_id"); err != nil {
			return fmt.Errorf("migrate metadata indexes: %w", err)
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

		// --- Phase 4: case-insensitive artist dedup (artists.name_norm) ---
		//
		// Сравнение имён в SQLite бинарное, и «Кино»/«кино» жили дублями.
		// Канон — name_norm (trim + lower, считает Go: SQLite LOWER
		// сворачивает только ASCII). Старые дубли сливаются в минимальный
		// id, связи перевешиваются, UNIQUE-индекс создаст AutoMigrate после.
		if ok, err := tableExists(tx, "artists"); err != nil {
			return fmt.Errorf("check artists: %w", err)
		} else if ok {
			if err := normalizeArtistNames(tx); err != nil {
				return fmt.Errorf("normalize artists: %w", err)
			}
			// Старый бинарный unique на name больше не нужен: norm строже.
			// AutoMigrate его не дропает, чистим здесь (как file_path).
			if err := dropUniqueIndexesOnColumn(tx, "artists", "name"); err != nil {
				return fmt.Errorf("migrate artists indexes: %w", err)
			}
		}

		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV2 добавляет video_kind. Новые таблицы каталога создаёт
// AutoMigrate; здесь только данные, которые AutoMigrate не заполняет.
func runMigrationsV2(db *gorm.DB) error {
	const schemaVersion = 2
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 2: %w", err)
		}
		if applied > 0 {
			return nil
		}
		hasMedia, err := tableExists(tx, "media")
		if err != nil {
			return fmt.Errorf("check media for v2: %w", err)
		}
		if hasMedia {
			hasVideoKind, err := tableHasColumn(tx, "media", "video_kind")
			if err != nil {
				return fmt.Errorf("check media.video_kind: %w", err)
			}
			if !hasVideoKind {
				if err := tx.Exec("ALTER TABLE media ADD COLUMN video_kind TEXT").Error; err != nil {
					return fmt.Errorf("add media.video_kind: %w", err)
				}
			}
			// Старые видео считаем фильмами. NULL у audio/image сохраняем.
			if err := repairVideoKind(tx); err != nil {
				return fmt.Errorf("repair media.video_kind: %w", err)
			}
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV3 исправляет данные, которые могла оставить v2 на уже
// существующей БД: аудио/картинки с video_kind, видео с мусорным kind.
func runMigrationsV3(db *gorm.DB) error {
	const schemaVersion = 3
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 3: %w", err)
		}
		if applied > 0 {
			return nil
		}
		if ok, err := tableExists(tx, "media"); err != nil {
			return fmt.Errorf("check media for v3: %w", err)
		} else if ok {
			hasVideoKind, err := tableHasColumn(tx, "media", "video_kind")
			if err != nil {
				return fmt.Errorf("check media.video_kind v3: %w", err)
			}
			if !hasVideoKind {
				// v2 должен был добавить колонку; при экзотической БД не валим старт.
				return tx.Create(&models.SchemaMigration{
					Version:   schemaVersion,
					AppliedAt: time.Now().UTC(),
				}).Error
			}
			if err := repairVideoKind(tx); err != nil {
				return fmt.Errorf("repair media.video_kind v3: %w", err)
			}
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV4 — нормализация прогресса и субтитров.
func runMigrationsV4(db *gorm.DB) error {
	const schemaVersion = 4
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 4: %w", err)
		}
		if applied > 0 {
			return nil
		}
		hasProgress, err := tableExists(tx, "watch_progresses")
		if err != nil {
			return fmt.Errorf("check watch_progresses: %w", err)
		}
		if hasProgress {
			hasOld, err := tableHasColumn(tx, "watch_progresses", "duration")
			if err != nil {
				return fmt.Errorf("check watch_progresses.duration: %w", err)
			}
			hasNew, err := tableHasColumn(tx, "watch_progresses", "reported_duration")
			if err != nil {
				return fmt.Errorf("check watch_progresses.reported_duration: %w", err)
			}
			if hasOld && !hasNew {
				if err := tx.Exec("ALTER TABLE watch_progresses RENAME COLUMN duration TO reported_duration").Error; err != nil {
					return fmt.Errorf("rename watch_progresses.duration: %w", err)
				}
			}
		}
		hasSubtitles, err := tableExists(tx, "subtitles")
		if err != nil {
			return fmt.Errorf("check subtitles: %w", err)
		}
		if hasSubtitles {
			// Оставляем новейшую дорожку на язык: дубликаты старого сканера.
			if err := tx.Exec(`DELETE FROM subtitles WHERE id NOT IN (
				SELECT MAX(id) FROM subtitles GROUP BY media_id, lang)`).Error; err != nil {
				return fmt.Errorf("dedupe subtitles: %w", err)
			}
			if err := tx.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_subtitles_media_lang
				ON subtitles(media_id, lang)`).Error; err != nil {
				return fmt.Errorf("create subtitles unique index: %w", err)
			}
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV9 — признак попытки извлечения встроенной обложки.
func runMigrationsV9(db *gorm.DB) error {
	const schemaVersion = 9
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 9: %w", err)
		}
		if applied > 0 {
			return nil
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV8 — системные теги формата, без которых вкладка «Фильмы»
// не может найти контент.
func runMigrationsV8(db *gorm.DB) error {
	const schemaVersion = 8
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 8: %w", err)
		}
		if applied > 0 {
			return nil
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV7 — теги и связи. Таблицы создаёт AutoMigrate; версия
// фиксирует этап для старых установок.
func runMigrationsV7(db *gorm.DB) error {
	const schemaVersion = 7
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 7: %w", err)
		}
		if applied > 0 {
			return nil
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV6 — прогресс существует только для видео.
func runMigrationsV6(db *gorm.DB) error {
	const schemaVersion = 6
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 6: %w", err)
		}
		if applied > 0 {
			return nil
		}
		if ok, err := tableExists(tx, "watch_progresses"); err != nil {
			return fmt.Errorf("check watch_progresses: %w", err)
		} else if ok {
			if ok, err := tableExists(tx, "media"); err != nil {
				return fmt.Errorf("check media for v6: %w", err)
			} else if ok {
				if err := tx.Exec(`DELETE FROM watch_progresses
					WHERE media_id IN (SELECT id FROM media WHERE type <> 'video')`).Error; err != nil {
					return fmt.Errorf("delete non-video progress: %w", err)
				}
			}
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

// runMigrationsV5 — metadata 1:1/external unique и source_media_id.
func runMigrationsV5(db *gorm.DB) error {
	const schemaVersion = 5
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.AutoMigrate(&models.SchemaMigration{}); err != nil {
			return fmt.Errorf("create schema_migrations: %w", err)
		}
		var applied int64
		if err := tx.Model(&models.SchemaMigration{}).
			Where("version = ?", schemaVersion).Count(&applied).Error; err != nil {
			return fmt.Errorf("check schema version 5: %w", err)
		}
		if applied > 0 {
			return nil
		}
		if ok, err := tableExists(tx, "media"); err != nil {
			return fmt.Errorf("check media for v5: %w", err)
		} else if ok {
			// Легаси-индекс мог остаться с pre-v1 и мешает клонированию
			// metadata с пустым external_id.
			if err := dropUniqueIndexesOnColumn(tx, "metadata", "external_id"); err != nil {
				return fmt.Errorf("drop legacy metadata external index: %w", err)
			}
			if err := tx.Exec(`UPDATE media SET metadata_id = NULL
				WHERE metadata_id IS NOT NULL
				  AND NOT EXISTS (SELECT 1 FROM metadata WHERE metadata.id = media.metadata_id)`).Error; err != nil {
				return fmt.Errorf("clean media.metadata_id: %w", err)
			}
			if err := makeMetadataOneToOne(tx); err != nil {
				return err
			}
			if err := dedupeMetadataExternal(tx); err != nil {
				return err
			}
			hasSource, err := tableHasColumn(tx, "media", "source_media_id")
			if err != nil {
				return fmt.Errorf("check media.source_media_id: %w", err)
			}
			if hasSource {
				if err := tx.Exec(`UPDATE media SET source_media_id = NULL
					WHERE source_media_id IS NOT NULL
					  AND NOT EXISTS (SELECT 1 FROM media src WHERE src.id = media.source_media_id)`).Error; err != nil {
					return fmt.Errorf("clean media.source_media_id: %w", err)
				}
			}
		}
		return tx.Create(&models.SchemaMigration{
			Version:   schemaVersion,
			AppliedAt: time.Now().UTC(),
		}).Error
	})
}

func dedupeMetadataExternal(tx *gorm.DB) error {
	var groups []struct {
		Source     string
		ExternalID string
		Keeper     uint
	}
	if err := tx.Raw(`SELECT source, external_id, MIN(id) AS keeper FROM metadata
		WHERE COALESCE(external_id, '') <> ''
		GROUP BY source, external_id HAVING COUNT(*) > 1`).Scan(&groups).Error; err != nil {
		return fmt.Errorf("find duplicate metadata: %w", err)
	}
	for _, group := range groups {
		var ids []uint
		if err := tx.Model(&models.Metadata{}).
			Where("source = ? AND external_id = ? AND id <> ?", group.Source, group.ExternalID, group.Keeper).
			Pluck("id", &ids).Error; err != nil {
			return fmt.Errorf("metadata dup ids: %w", err)
		}
		if len(ids) == 0 {
			continue
		}
		// Поля дублей сохраняем: чистим только внешнюю идентичность,
		// иначе ручные постеры/рейтинги/описания терялись бы.
		if err := tx.Model(&models.Metadata{}).Where("id IN ?", ids).
			Update("external_id", "").Error; err != nil {
			return fmt.Errorf("clear duplicate metadata external id: %w", err)
		}
	}
	return nil
}

func makeMetadataOneToOne(tx *gorm.DB) error {
	var metadataIDs []uint
	if err := tx.Unscoped().Model(&models.Media{}).Where("metadata_id IS NOT NULL").
		Group("metadata_id").Having("COUNT(*) > 1").Pluck("metadata_id", &metadataIDs).Error; err != nil {
		return fmt.Errorf("find shared metadata: %w", err)
	}
	for _, metadataID := range metadataIDs {
		var medias []models.Media
		if err := tx.Unscoped().Where("metadata_id = ?", metadataID).Order("id").Find(&medias).Error; err != nil {
			return err
		}
		var original models.Metadata
		if err := tx.First(&original, metadataID).Error; err != nil {
			return err
		}
		for _, media := range medias[1:] {
			clone := original
			clone.ID = 0
			// У клона та же внешняя идентичность недопустима: unique
			// (source, external_id) остаётся за оригиналом.
			clone.ExternalID = ""
			if err := tx.Create(&clone).Error; err != nil {
				return fmt.Errorf("clone metadata: %w", err)
			}
			if err := tx.Unscoped().Model(&models.Media{}).Where("id = ?", media.ID).
				Update("metadata_id", clone.ID).Error; err != nil {
				return fmt.Errorf("repoint media metadata: %w", err)
			}
		}
	}
	return nil
}

// createMediaSourceTriggers защищает source_media_id без пересборки media.
func createMediaSourceTriggers(db *gorm.DB) error {
	exists := `NEW.source_media_id IS NOT NULL AND NOT EXISTS (
		SELECT 1 FROM media WHERE id = NEW.source_media_id)`
	queries := []string{
		`DROP TRIGGER IF EXISTS media_source_insert`,
		`CREATE TRIGGER media_source_insert BEFORE INSERT ON media
		FOR EACH ROW WHEN ` + exists + `
		BEGIN SELECT RAISE(ABORT, 'media_source_missing'); END`,
		`DROP TRIGGER IF EXISTS media_source_update`,
		`CREATE TRIGGER media_source_update BEFORE UPDATE OF source_media_id ON media
		FOR EACH ROW WHEN NEW.source_media_id IS NOT OLD.source_media_id AND ` + exists + `
		BEGIN SELECT RAISE(ABORT, 'media_source_missing'); END`,
		`DROP TRIGGER IF EXISTS media_source_delete`,
		`CREATE TRIGGER media_source_delete AFTER DELETE ON media
		FOR EACH ROW BEGIN
			UPDATE media SET source_media_id = NULL WHERE source_media_id = OLD.id;
		END`,
	}
	return db.Transaction(func(tx *gorm.DB) error {
		for _, query := range queries {
			if err := tx.Exec(query).Error; err != nil {
				return fmt.Errorf("create media source trigger: %w", err)
			}
		}
		return nil
	})
}

// repairVideoKind приводит невалидные значения к инварианту:
// video -> movie/episode, всё остальное -> NULL.
func repairVideoKind(tx *gorm.DB) error {
	return tx.Exec(`UPDATE media
		SET video_kind = CASE WHEN type = 'video' THEN 'movie' ELSE NULL END
		WHERE (type = 'video' AND (video_kind IS NULL OR video_kind NOT IN ('movie','episode')))
		   OR (COALESCE(type, '') <> 'video' AND video_kind IS NOT NULL)`).Error
}

// normalizeArtistNames backfills artists.name_norm (Go lower — юникодный,
// в отличие от SQLite LOWER) and merges case-duplicates into the minimal
// id, repointing media_artists and favorites. Idempotent: re-runs change
// nothing once norms are filled and unique.
func normalizeArtistNames(tx *gorm.DB) error {
	if has, err := tableHasColumn(tx, "artists", "name_norm"); err != nil {
		return fmt.Errorf("check artists.name_norm: %w", err)
	} else if !has {
		if err := tx.Exec("ALTER TABLE artists ADD COLUMN name_norm TEXT").Error; err != nil {
			return fmt.Errorf("add artists.name_norm: %w", err)
		}
	}

	var artists []models.Artist
	if err := tx.Find(&artists).Error; err != nil {
		return fmt.Errorf("list artists: %w", err)
	}
	for i := range artists {
		norm := normArtistName(artists[i].Name)
		if artists[i].NameNorm == norm {
			continue
		}
		if err := tx.Model(&models.Artist{}).
			Where("id = ?", artists[i].ID).
			Update("name_norm", norm).Error; err != nil {
			return fmt.Errorf("backfill artists.name_norm: %w", err)
		}
	}

	var groups []struct {
		Norm   string
		Keeper uint
		IDs    string
	}
	if err := tx.Raw(`SELECT name_norm AS norm, MIN(id) AS keeper,
		GROUP_CONCAT(id) AS ids FROM artists
		GROUP BY name_norm HAVING COUNT(*) > 1`).Scan(&groups).Error; err != nil {
		return fmt.Errorf("find duplicate artists: %w", err)
	}
	hasMediaArtists, err := tableExists(tx, "media_artists")
	if err != nil {
		return fmt.Errorf("check media_artists: %w", err)
	}
	hasFavArtistID, err := tableHasColumn(tx, "favorites", "artist_id")
	if err != nil {
		return fmt.Errorf("check favorites.artist_id: %w", err)
	}
	for _, group := range groups {
		var dupes []uint
		for _, part := range strings.Split(group.IDs, ",") {
			var id uint64
			if _, err := fmt.Sscanf(part, "%d", &id); err != nil {
				return fmt.Errorf("parse duplicate artist id: %w", err)
			}
			if uint(id) != group.Keeper {
				dupes = append(dupes, uint(id))
			}
		}
		if len(dupes) == 0 {
			continue
		}
		if hasMediaArtists {
			// UPDATE OR IGNORE: строка stays on the dupe only when the
			// keeper link already exists; leftovers are deleted below.
			if err := tx.Exec(`UPDATE OR IGNORE media_artists SET artist_id = ?
				WHERE artist_id IN ?`, group.Keeper, dupes).Error; err != nil {
				return fmt.Errorf("repoint media_artists: %w", err)
			}
			if err := tx.Exec(`DELETE FROM media_artists
				WHERE artist_id IN ?`, dupes).Error; err != nil {
				return fmt.Errorf("delete duplicate media_artists: %w", err)
			}
		}
		if hasFavArtistID {
			if err := tx.Exec(`UPDATE OR IGNORE favorites SET artist_id = ?
				WHERE artist_id IN ?`, group.Keeper, dupes).Error; err != nil {
				return fmt.Errorf("repoint favorite artists: %w", err)
			}
			if err := tx.Exec(`DELETE FROM favorites
				WHERE artist_id IN ?`, dupes).Error; err != nil {
				return fmt.Errorf("delete duplicate favorite artists: %w", err)
			}
		}
		if err := tx.Exec(`DELETE FROM artists WHERE id IN ?`, dupes).Error; err != nil {
			return fmt.Errorf("delete duplicate artists: %w", err)
		}
		log.Printf("migration: merged %d duplicate artist(s) into id=%d (%s)",
			len(dupes), group.Keeper, group.Norm)
	}
	return nil
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
		// Системные автоиндексы inline-ограничений (UNIQUE в CREATE TABLE)
		// дропать нельзя: DROP INDEX на них уронит миграцию и старт
		// сервера целиком. Сейчас таких нет (GORM создаёт отдельные
		// индексы), guard — на будущее.
		if strings.HasPrefix(idx.Name, "sqlite_autoindex_") {
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
