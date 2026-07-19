package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type ProgressStore struct {
	db *gorm.DB
}

func NewProgressRepository(db *gorm.DB) *ProgressStore {
	return &ProgressStore{db: db}
}

func (r *ProgressStore) FindByUser(ctx context.Context, userID uint) ([]models.WatchProgress, error) {
	var progress []models.WatchProgress
	err := r.db.WithContext(ctx).Where("user_id = ?", userID).Find(&progress).Error
	return progress, err
}

func (r *ProgressStore) FindByUserAndMedia(ctx context.Context, userID, mediaID uint) (*models.WatchProgress, error) {
	var progress models.WatchProgress
	err := r.db.WithContext(ctx).Where("user_id = ? AND media_id = ?", userID, mediaID).First(&progress).Error
	return &progress, err
}

func (r *ProgressStore) Upsert(ctx context.Context, progress *models.WatchProgress) error {
	return r.db.WithContext(ctx).Save(progress).Error
}

func (r *ProgressStore) Delete(ctx context.Context, userID, mediaID uint) error {
	return r.db.WithContext(ctx).Where("user_id = ? AND media_id = ?", userID, mediaID).Delete(&models.WatchProgress{}).Error
}
