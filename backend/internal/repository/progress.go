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

func (r *ProgressStore) FindByUser(ctx context.Context, userID uint, limit, offset int) ([]models.WatchProgress, int64, error) {
	var progress []models.WatchProgress
	var total int64
	query := r.db.WithContext(ctx).Model(&models.WatchProgress{}).Where("user_id = ?", userID)
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if limit > 0 {
		query = query.Limit(limit)
	}
	if offset > 0 {
		query = query.Offset(offset)
	}
	err := query.Find(&progress).Error
	return progress, total, err
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
