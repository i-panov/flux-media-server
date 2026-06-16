package repository

import (
	"flux/internal/models"

	"gorm.io/gorm"
)

type MediaRepository struct {
	db *gorm.DB
}

func NewMediaRepository(db *gorm.DB) *MediaRepository {
	return &MediaRepository{db: db}
}

func (r *MediaRepository) FindAll(filters map[string]interface{}) ([]models.Media, error) {
	var media []models.Media
	query := r.db.Preload("Metadata")

	if mediaType, ok := filters["type"]; ok {
		query = query.Where("type = ?", mediaType)
	}
	if year, ok := filters["year"]; ok {
		query = query.Where("year = ?", year)
	}

	err := query.Find(&media).Error
	return media, err
}

func (r *MediaRepository) FindByID(id uint) (*models.Media, error) {
	var media models.Media
	err := r.db.Preload("Metadata").First(&media, id).Error
	return &media, err
}

func (r *MediaRepository) FindByPath(path string) (*models.Media, error) {
	var media models.Media
	err := r.db.Where("file_path = ?", path).First(&media).Error
	return &media, err
}

func (r *MediaRepository) Create(media *models.Media) error {
	return r.db.Create(media).Error
}

func (r *MediaRepository) Update(media *models.Media) error {
	return r.db.Save(media).Error
}

func (r *MediaRepository) Delete(id uint) error {
	return r.db.Delete(&models.Media{}, id).Error
}
