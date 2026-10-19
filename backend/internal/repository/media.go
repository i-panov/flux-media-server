package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"flux/internal/metadata"
	"flux/internal/models"

	"gorm.io/gorm"
)

type MediaStore struct {
	db *gorm.DB
}

func NewMediaRepository(db *gorm.DB) *MediaStore {
	return &MediaStore{db: db}
}

func (r *MediaStore) FindAll(ctx context.Context, filters MediaFilters, limit, offset int) ([]models.Media, int64, error) {
	var media []models.Media
	var total int64
	query := r.db.WithContext(ctx).
		Preload("Metadata")

	if filters.Type != "" {
		query = query.Where("type = ?", filters.Type)
	}
	if filters.Year != 0 {
		query = query.Where("year = ?", filters.Year)
	}
	if filters.Q != "" {
		// Экранируем спецсимволы LIKE из пользовательского ввода: иначе
		// «%» и «_» трактуются как шаблон, а не как литеральные символы.
		like := "%" + escapeLike(filters.Q) + "%"
		query = query.Where(
			`title LIKE ? ESCAPE '\' OR album LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\'
			 OR EXISTS (SELECT 1 FROM media_artists ma
			             JOIN artists a ON a.id = ma.artist_id
			             WHERE ma.media_id = media.id AND a.name LIKE ? ESCAPE '\')`,
			like, like, like, like,
		)
	}

	if err := query.Model(&models.Media{}).Count(&total).Error; err != nil {
		return nil, 0, err
	}

	if limit > 0 {
		query = query.Limit(limit)
	}
	if offset > 0 {
		query = query.Offset(offset)
	}

	// ORDER BY is required for stable pagination: without it SQLite does not
	// guarantee row order, causing duplicates/missing items between pages.
	query = query.Order("media.id ASC")

	err := query.Find(&media).Error
	if err != nil {
		return nil, 0, err
	}

	// Load artists separately to avoid the GORM many2many preload cartesian
	// product bug (see LoadArtistsForMedia).
	if loadErr := LoadArtistsForMedia(r.db.WithContext(ctx), media); loadErr != nil {
		return nil, 0, loadErr
	}

	return media, total, err
}

func (r *MediaStore) FindByID(ctx context.Context, id uint) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).
		Preload("Metadata").
		First(&media, id).Error
	if err != nil {
		return &media, err
	}

	mediaSlice := []models.Media{media}
	if err := LoadArtistsForMedia(r.db.WithContext(ctx), mediaSlice); err != nil {
		return &media, err
	}
	media.Artists = mediaSlice[0].Artists
	return &media, nil
}

func (r *MediaStore) FindByPath(ctx context.Context, path string) (*models.Media, error) {
	var media models.Media
	// Unscoped: дедуп видит и корзину — файл с trashed-строкой не
	// импортируется дублем, а пропуск дубликата решает вызывающий
	// (сканер) по DeletedAt.
	err := r.db.WithContext(ctx).Unscoped().
		Preload("Metadata").
		Where("file_path = ?", path).First(&media).Error
	if err != nil {
		return &media, err
	}

	mediaSlice := []models.Media{media}
	if err := LoadArtistsForMedia(r.db.WithContext(ctx), mediaSlice); err != nil {
		return &media, err
	}
	media.Artists = mediaSlice[0].Artists
	return &media, nil
}

// FindByPathBasic ищет медиа по пути ОДНИМ дешёвым SELECT без Preload
// (Metadata/Artists). Для горячих путей, где полный объект не нужен
// (например, сканер при полном скане: FindByPath делает 3 запроса на файл).
// Unscoped — как FindByPath: trashed-строка тоже «существует».
func (r *MediaStore) FindByPathBasic(ctx context.Context, path string) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).Unscoped().Where("file_path = ?", path).First(&media).Error
	return &media, err
}

// FindVideosMissingDimensions отдаёт живые видео без размеров кадра.
//
// Фильтр по ОБОИМ размерам (width = 0 OR height = 0): клиенту нужна
// пара, а не одно число — при width > 0 и height = 0 запись не
// заполнилась бы никогда (фильтр по width её не видел), и пропорции
// остались бы неопределёнными.
//
// Мягкий фильтр: битый файл, который ffprobe не осилил, не должен
// заставлять заливку переспрашивать его при каждом старте — достаточно,
// чтобы он не уехал в конец очереди навсегда. Порядок по ID: заливка
// идёт до конца, а не крутится по кругу.
func (r *MediaStore) FindVideosMissingDimensions(ctx context.Context, limit int) ([]models.Media, error) {
	if limit <= 0 {
		limit = 50
	}
	var media []models.Media
	err := r.db.WithContext(ctx).
		Where("type = ? AND (width = 0 OR height = 0)", models.MediaTypeVideo).
		Order("id ASC").
		Limit(limit).
		Find(&media).Error
	return media, err
}

// UpdateDimensions записывает только размеры кадра.
//
// Отдельный метод вместо Update: Update трогает ассоциации (Artists),
// и вызов на записи без предзагруженных артистов стирал связи видео с
// артистами. Здесь пишутся два технических числа — ничего больше.
func (r *MediaStore) UpdateDimensions(ctx context.Context, id uint, width, height int) error {
	if id == 0 {
		return errors.New("repository: media ID required for UpdateDimensions")
	}
	return r.db.WithContext(ctx).
		Model(&models.Media{}).
		Where("id = ?", id).
		Updates(map[string]interface{}{
			"width":  width,
			"height": height,
		}).Error
}

// FindByIDs возвращает медиа по списку ID (порядок не гарантируется —
// сортировка по media.id ASC). Артисты грузятся пакетно, как в FindAll.
func (r *MediaStore) FindByIDs(ctx context.Context, ids []uint) ([]models.Media, error) {
	if len(ids) == 0 {
		return []models.Media{}, nil
	}
	var media []models.Media
	if err := r.db.WithContext(ctx).
		Preload("Metadata").
		Where("media.id IN ?", ids).
		Order("media.id ASC").
		Find(&media).Error; err != nil {
		return nil, err
	}
	if err := LoadArtistsForMedia(r.db.WithContext(ctx), media); err != nil {
		return nil, err
	}
	return media, nil
}

func (r *MediaStore) FindByHash(ctx context.Context, hash string) (*models.Media, error) {
	var media models.Media
	// Unscoped: дедуп загрузок видит корзину — повторная загрузка того
	// же файла честно отвечает 409, а не плодит дубль.
	// Детерминированный порядок: живые строки раньше trashed
	// (в SQLite NULL меньше всего, ASC ставит их первыми) — иначе
	// при живом дубле вернулась бы корзина и upload пошёл бы
	// по ветке restore вместо честного 409.
	err := r.db.WithContext(ctx).Unscoped().Where("file_hash = ?", hash).Order("deleted_at").Order("id").First(&media).Error
	return &media, err
}

// FindBySourceMediaID ищет аудиотрек, извлечённый из видео mediaID.
// Soft-deleted исключаются дефолтным скоупом gorm: удалённый трек
// разрывает связку, и экран видео снова показывает кнопку извлечения.
func (r *MediaStore) FindBySourceMediaID(ctx context.Context, mediaID uint) (*models.Media, error) {
	var media models.Media
	// Детерминированный порядок: дублей быть не должно (дедуп очереди),
	// но без Order при дубле вернулся бы произвольный.
	err := r.db.WithContext(ctx).Where("source_media_id = ?", mediaID).Order("id").First(&media).Error
	return &media, err
}

func (r *MediaStore) FindByPathPrefix(ctx context.Context, prefix string, limit, offset int) ([]models.Media, int64, error) {
	var media []models.Media
	var total int64
	// Экранируем спецсимволы LIKE в префиксе: неэкранированное «_» матчит
	// любой символ, и sweep при скане одной библиотеки мог удалить записи
	// соседней с похожим путём (например, /data/my_media vs /data/my-media).
	query := r.db.WithContext(ctx).Where("file_path LIKE ? ESCAPE '\\'", escapeLike(prefix)+"%").Model(&models.Media{})

	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	if limit > 0 {
		query = query.Limit(limit)
	}
	if offset > 0 {
		query = query.Offset(offset)
	}

	query = query.Order("media.id ASC")
	err := query.Find(&media).Error
	return media, total, err
}

func (r *MediaStore) Create(ctx context.Context, media *models.Media) error {
	return r.db.WithContext(ctx).Create(media).Error
}

// Update обновляет только непустые поля media и полную замену ассоциаций:
// Artists (если список передан) и Metadata (upsert при наличии). Нулевые
// значения скалярных полей НЕ записываются — частично заполненный Media
// (например, из FindByHash без Preload) не затирает Description/Genre/
// Duration/Year и прочие существующие данные.
func (r *MediaStore) Update(ctx context.Context, media *models.Media) error {
	if media.ID == 0 {
		return errors.New("repository: media ID required for Update")
	}

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return updateMediaTx(tx, media, nil)
	})
}

// UpdateWithSourceURL — то же, что Update, плюс безусловная запись ссылки
// на источник (включая пустую строку = очистка), всё в одной транзакции.
func (r *MediaStore) UpdateWithSourceURL(ctx context.Context, media *models.Media, sourceURL *string) error {
	if media.ID == 0 {
		return errors.New("repository: media ID required for UpdateWithSourceURL")
	}

	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return updateMediaTx(tx, media, sourceURL)
	})
}

func updateMediaTx(tx *gorm.DB, media *models.Media, sourceURL *string) error {
	// Запись существует? Без проверки удаление между Find и Update — или
	// вызов в обход чтения вообще — дало бы 200 с фантомом (при пустом
	// updates не пишется ничего, и пропажа видна только здесь).
	// Один индексированный COUNT по первичному ключу на фоне ffprobe
	// и файлового IO незаметен даже на горячем пути сканера.
	var count int64
	if err := tx.Model(&models.Media{}).Where("id = ?", media.ID).Count(&count).Error; err != nil {
		return err
	}
	if count == 0 {
		return gorm.ErrRecordNotFound
	}

	// Defense-in-depth: ссылку перепроверяем и здесь, а не только в
	// хендлере — прямой вызов репозитория в обход валидации не должен
	// положить мусор в БД.
	if sourceURL != nil {
		normalized, err := metadata.NormalizeSourceURL(*sourceURL)
		if err != nil {
			return err
		}
		*sourceURL = normalized
	}

	// Артисты: nil означает «не загружено» (запись прочитана без
	// Preload), а НЕ «связей нет». resolveArtists на nil вернул бы
	// не-nil пустой срез, и проверка ниже сочла бы, что связи надо
	// заменить — Replace с пустым списком удаляет все строки
	// media_artists у записи. Так терялись артисты у видео, к которым
	// применили Update без предзагруженных артистов (например, при
	// бэкфилле размеров кадра).
	//
	// Поэтому пустой срез (осознанное «связей нет») и nil (не знаем)
	// различаются, и ассоциация трогается только в первом случае.
	artistsLoaded := media.Artists != nil
	if artistsLoaded {
		resolved, err := resolveArtists(tx, media.Artists)
		if err != nil {
			return err
		}
		media.Artists = resolved
	}

	updates := make(map[string]interface{})
	if media.Title != "" {
		updates["title"] = media.Title
	}
	if media.Filename != "" {
		updates["filename"] = media.Filename
	}
	if media.Year != 0 {
		updates["year"] = media.Year
	}
	if media.Description != "" {
		updates["description"] = media.Description
	}
	if media.Type != "" {
		updates["type"] = media.Type
	}
	if media.Album != "" {
		updates["album"] = media.Album
	}
	if media.Genre != "" {
		updates["genre"] = media.Genre
	}
	if media.Duration != 0 {
		updates["duration"] = media.Duration
	}
	if media.Width != 0 {
		updates["width"] = media.Width
	}
	if media.Height != 0 {
		updates["height"] = media.Height
	}
	if media.FilePath != "" {
		updates["file_path"] = media.FilePath
	}
	if media.FileSize != 0 {
		updates["file_size"] = media.FileSize
	}
	if media.FileHash != "" {
		updates["file_hash"] = media.FileHash
	}
	if media.QuickHash != "" {
		updates["quick_hash"] = media.QuickHash
	}
	if media.ThumbnailURL != "" {
		updates["thumbnail_url"] = media.ThumbnailURL
	}
	if media.CoverURL != "" {
		updates["cover_url"] = media.CoverURL
	}
	if media.MetadataID != nil && media.Metadata == nil {
		updates["metadata_id"] = *media.MetadataID
	}
	if sourceURL != nil {
		updates["source_url"] = *sourceURL
	}

	if len(updates) > 0 {
		if err := tx.Model(media).Updates(updates).Error; err != nil {
			return err
		}
	}

	// Has-one Metadata сохраняется явно: Updates не трогает ассоциации,
	// а старый Save(media) сохранял её через upsert.
	if media.Metadata != nil {
		if err := tx.Save(media.Metadata).Error; err != nil {
			return err
		}
		if media.MetadataID == nil || *media.MetadataID != media.Metadata.ID {
			if err := tx.Model(media).Update("metadata_id", media.Metadata.ID).Error; err != nil {
				return err
			}
		}
	}

	// Связи артистов трогаем только если они были загружены (см. выше
	// про nil vs пустой срез).
	if artistsLoaded {
		return tx.Model(media).Association("Artists").Replace(&media.Artists)
	}
	return nil
}

// resolveArtists находит артистов по имени (find-or-create) и возвращает
// список с заполненными ID. Пустые имена отбрасываются: запись артиста с
// пустым именем привела бы к UNIQUE-ошибке при повторном Replace.
func resolveArtists(db *gorm.DB, artists []models.Artist) ([]models.Artist, error) {
	resolved := make([]models.Artist, 0, len(artists))
	for _, a := range artists {
		name := strings.TrimSpace(a.Name)
		if name == "" {
			continue
		}
		var existing models.Artist
		err := db.Where("name = ?", name).First(&existing).Error
		if err == nil {
			resolved = append(resolved, existing)
			continue
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		a.Name = name
		if err := db.Create(&a).Error; err != nil {
			// Маскируем только реальную гонку (UNIQUE-нарушение и запись уже
			// существует); прочие сбои БД возвращаются как есть.
			if !isUniqueViolation(err) {
				return nil, err
			}
			if err2 := db.Where("name = ?", name).First(&existing).Error; err2 != nil {
				return nil, err
			}
			resolved = append(resolved, existing)
			continue
		}
		resolved = append(resolved, a)
	}
	return resolved, nil
}

// escapeLike экранирует спецсимволы LIKE (% и _) во входе пользователя,
// чтобы поиск был посимвольным, а не по шаблону.
func escapeLike(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `%`, `\%`)
	s = strings.ReplaceAll(s, `_`, `\_`)
	return s
}

func (r *MediaStore) Delete(ctx context.Context, id uint) error {
	// Корзина: только флаг, без каскадов и без файлов — связи
	// (избранное, прогресс, коллекции) и восстановление целы.
	// Файл остаётся на диске: сканер пропускает trashed-строки
	// и дублей не создаёт. Навсегда — PurgeMedia.
	return r.db.WithContext(ctx).Model(&models.Media{}).
		Where("id = ?", id).
		Update("deleted_at", time.Now().UTC()).Error
}

// ErrPathConflict — восстановление невозможно: путь уже занят живой строкой.
var ErrPathConflict = errors.New("live media already exists at this path")

// RestoreMedia возвращает медиа из корзины. Файл всё время лежал
// на диске — пересканировать не нужно. Живой дубль по пути — 409.
func (r *MediaStore) RestoreMedia(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var media models.Media
		if err := tx.Unscoped().First(&media, id).Error; err != nil {
			return err
		}
		if !media.DeletedAt.Valid {
			// Живая строка — восстанавливать нечего: 404 как у purge
			// и коллекций, а не молчаливый 200.
			return ErrNotInTrash
		}
		var live int64
		if err := tx.Model(&models.Media{}).
			Where("file_path = ? AND id <> ?", media.FilePath, id).
			Count(&live).Error; err != nil {
			return err
		}
		if live > 0 {
			return ErrPathConflict
		}
		return tx.Unscoped().Model(&models.Media{}).
			Where("id = ?", id).
			Update("deleted_at", nil).Error
	})
}

// PurgeMedia сносит медиа навсегда: связи каскадом, строка — hard,
// файлы стирает вызывающий хендлер (как раньше делал Delete).
// Metadata сносится тоже, но только если на неё никто больше
// не ссылается (защита от shared-строк).
func (r *MediaStore) PurgeMedia(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var media models.Media
		if err := tx.Unscoped().Select("id", "metadata_id").First(&media, id).Error; err != nil {
			return err
		}
		if err := cascadeDelete(tx, "media_id", id,
			&models.Favorite{}, &models.WatchProgress{}, &models.Lyrics{},
			&models.CollectionItem{}, &models.MediaArtist{}); err != nil {
			return err
		}
		if err := tx.Unscoped().Delete(&models.Media{}, id).Error; err != nil {
			return err
		}
		if media.MetadataID != nil {
			var refs int64
			if err := tx.Model(&models.Media{}).Unscoped().
				Where("metadata_id = ?", *media.MetadataID).
				Count(&refs).Error; err != nil {
				return err
			}
			if refs == 0 {
				if err := tx.Unscoped().Delete(&models.Metadata{}, *media.MetadataID).Error; err != nil {
					return err
				}
			}
		}
		return nil
	})
}

// FindTrashedMedia грузит trashed-строку медиа. Живая или
// отсутствующая — ErrNotInTrash / NotFound (purge и restore работают
// только с корзиной).
func (r *MediaStore) FindTrashedMedia(ctx context.Context, id uint) (*models.Media, error) {
	var media models.Media
	if err := r.db.WithContext(ctx).Unscoped().First(&media, id).Error; err != nil {
		return nil, err
	}
	if !media.DeletedAt.Valid {
		return nil, ErrNotInTrash
	}
	return &media, nil
}

// TrashedMedia — плоский список корзины (вложенности у медиа нет).
func (r *MediaStore) TrashedMedia(ctx context.Context, limit, offset int) ([]models.Media, error) {
	var media []models.Media
	q := r.db.WithContext(ctx).Unscoped().
		Where("deleted_at IS NOT NULL").
		Order("deleted_at DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	if offset > 0 {
		q = q.Offset(offset)
	}
	return media, q.Find(&media).Error
}
