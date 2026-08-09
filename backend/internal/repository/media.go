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

func (r *MediaStore) FindAll(ctx context.Context, filters map[string]interface{}, limit, offset int) ([]models.Media, int64, error) {
	var media []models.Media
	var total int64
	query := r.db.WithContext(ctx).
		Preload("Metadata")

	if mediaType, ok := filters["type"]; ok {
		query = query.Where("type = ?", mediaType)
	}
	if year, ok := filters["year"]; ok {
		query = query.Where("year = ?", year)
	}
	if q, ok := filters["q"]; ok {
		if searchTerm, ok := q.(string); ok && searchTerm != "" {
			like := "%" + searchTerm + "%"
			query = query.Where(
				`title LIKE ? OR album LIKE ? OR description LIKE ?
				 OR EXISTS (SELECT 1 FROM media_artists ma
				             JOIN artists a ON a.id = ma.artist_id
				             WHERE ma.media_id = media.id AND a.name LIKE ?)`,
				like, like, like, like,
			)
		}
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
	_ = LoadArtistsForMedia(r.db.WithContext(ctx), mediaSlice)
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
	_ = LoadArtistsForMedia(r.db.WithContext(ctx), mediaSlice)
	media.Artists = mediaSlice[0].Artists
	return &media, nil
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

func (r *MediaStore) Update(ctx context.Context, media *models.Media) error {
	// Resolve artist names to IDs (find-or-create) before saving.
	for i := range media.Artists {
		name := strings.TrimSpace(media.Artists[i].Name)
		if name == "" {
			continue
		}
		var existing models.Artist
		err := r.db.WithContext(ctx).Where("name = ?", name).First(&existing).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			media.Artists[i].Name = name
			if err := r.db.WithContext(ctx).Create(&media.Artists[i]).Error; err != nil {
				// Race: another goroutine created it.
				if err2 := r.db.WithContext(ctx).Where("name = ?", name).First(&existing).Error; err2 != nil {
					return err
				}
				media.Artists[i] = existing
			}
		} else if err != nil {
			return err
		} else {
			media.Artists[i] = existing
		}
	}

	// Save media record and replace artist associations in a single
	// transaction. FullSaveAssociations is NOT used because it would
	// duplicate the artist-saving work and reset join-table positions.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Omit("Artists").Save(media).Error; err != nil {
			return err
		}
		if media.Artists != nil {
			return tx.Model(media).Association("Artists").Replace(&media.Artists)
		}
		return nil
	})
}

func (r *MediaStore) Delete(ctx context.Context, id uint) error {
	// Delete the media record and its dependent rows (favorites, progress,
	// lyrics, collection items) atomically to avoid orphaned data.
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("media_id = ?", id).Delete(&models.Favorite{}).Error; err != nil {
			return err
		}
		if err := tx.Where("media_id = ?", id).Delete(&models.WatchProgress{}).Error; err != nil {
			return err
		}
		if err := tx.Where("media_id = ?", id).Delete(&models.Lyrics{}).Error; err != nil {
			return err
		}
		if err := tx.Where("media_id = ?", id).Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		return tx.Delete(&models.Media{}, id).Error
	})
}
