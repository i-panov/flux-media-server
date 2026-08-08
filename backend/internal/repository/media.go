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
		Preload("Metadata").
		Preload("Artists", func(db *gorm.DB) *gorm.DB {
			return db.Joins("JOIN media_artists ON media_artists.artist_id = artists.id").Order("media_artists.position ASC")
		})

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

	err := query.Find(&media).Error
	return media, total, err
}

func (r *MediaStore) FindByID(ctx context.Context, id uint) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).
		Preload("Metadata").
		Preload("Artists", func(db *gorm.DB) *gorm.DB {
			return db.Joins("JOIN media_artists ON media_artists.artist_id = artists.id").Order("media_artists.position ASC")
		}).
		First(&media, id).Error
	return &media, err
}

func (r *MediaStore) FindByPath(ctx context.Context, path string) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).
		Preload("Artists", func(db *gorm.DB) *gorm.DB {
			return db.Joins("JOIN media_artists ON media_artists.artist_id = artists.id").Order("media_artists.position ASC")
		}).
		Where("file_path = ?", path).First(&media).Error
	return &media, err
}

func (r *MediaStore) FindByHash(ctx context.Context, hash string) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).Where("file_hash = ?", hash).First(&media).Error
	return &media, err
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

	if err := r.db.WithContext(ctx).Session(&gorm.Session{FullSaveAssociations: true}).Save(media).Error; err != nil {
		return err
	}

	// Replace many-to-many associations so removed artists are unlinked.
	if media.Artists != nil {
		if err := r.db.WithContext(ctx).Model(media).Association("Artists").Replace(&media.Artists); err != nil {
			return err
		}
	}
	return nil
}

func (r *MediaStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Delete(&models.Media{}, id).Error
}
