package repository

import (
	"context"
	"errors"
	"strings"

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
	err := r.db.WithContext(ctx).
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
func (r *MediaStore) FindByPathBasic(ctx context.Context, path string) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).Where("file_path = ?", path).First(&media).Error
	return &media, err
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
	err := r.db.WithContext(ctx).Where("file_hash = ?", hash).First(&media).Error
	return &media, err
}

func (r *MediaStore) FindByPathPrefix(ctx context.Context, prefix string, limit, offset int) ([]models.Media, int64, error) {
	var media []models.Media
	var total int64
	query := r.db.WithContext(ctx).Where("file_path LIKE ?", prefix+"%").Model(&models.Media{})

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
		artists, err := resolveArtists(tx, media.Artists)
		if err != nil {
			return err
		}
		media.Artists = artists

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

		if media.Artists != nil {
			return tx.Model(media).Association("Artists").Replace(&media.Artists)
		}
		return nil
	})
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
	// Delete the media record and its dependent rows (favorites, progress,
	// lyrics, collection items, artist links) atomically to avoid orphaned data.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := cascadeDelete(tx, "media_id", id,
			&models.Favorite{}, &models.WatchProgress{}, &models.Lyrics{},
			&models.CollectionItem{}, &models.MediaArtist{}); err != nil {
			return err
		}
		return tx.Delete(&models.Media{}, id).Error
	})
}
