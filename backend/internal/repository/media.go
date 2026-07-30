package repository

import (
	"context"

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
	query := r.db.WithContext(ctx).Preload("Metadata")

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
				"title LIKE ? OR artist LIKE ? OR album LIKE ? OR description LIKE ?",
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
	err := r.db.WithContext(ctx).Preload("Metadata").First(&media, id).Error
	return &media, err
}

func (r *MediaStore) FindByPath(ctx context.Context, path string) (*models.Media, error) {
	var media models.Media
	err := r.db.WithContext(ctx).Where("file_path = ?", path).First(&media).Error
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
	return r.db.WithContext(ctx).Session(&gorm.Session{FullSaveAssociations: true}).Save(media).Error
}

func (r *MediaStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Delete(&models.Media{}, id).Error
}
