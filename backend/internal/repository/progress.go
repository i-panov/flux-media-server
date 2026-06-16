package repository

import (
	"flux/internal/models"

	"gorm.io/gorm"
)

type ProgressRepository struct {
	db *gorm.DB
}

func NewProgressRepository(db *gorm.DB) *ProgressRepository {
	return &ProgressRepository{db: db}
}

func (r *ProgressRepository) FindByUser(userID uint) ([]models.WatchProgress, error) {
	var progress []models.WatchProgress
	err := r.db.Where("user_id = ?", userID).Find(&progress).Error
	return progress, err
}

func (r *ProgressRepository) FindByUserAndMedia(userID, mediaID uint) (*models.WatchProgress, error) {
	var progress models.WatchProgress
	err := r.db.Where("user_id = ? AND media_id = ?", userID, mediaID).First(&progress).Error
	return &progress, err
}

func (r *ProgressRepository) Upsert(progress *models.WatchProgress) error {
	return r.db.Save(progress).Error
}

func (r *ProgressRepository) Delete(userID, mediaID uint) error {
	return r.db.Where("user_id = ? AND media_id = ?", userID, mediaID).Delete(&models.WatchProgress{}).Error
}
