package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type ClipStore struct {
	db *gorm.DB
}

func NewClipRepository(db *gorm.DB) *ClipStore {
	return &ClipStore{db: db}
}

func (r *ClipStore) Create(ctx context.Context, task *models.ClipTask) error {
	return r.db.WithContext(ctx).Create(task).Error
}

func (r *ClipStore) Update(ctx context.Context, id uint, updates map[string]any) error {
	return r.db.WithContext(ctx).Model(&models.ClipTask{}).Where("id = ?", id).
		Updates(updates).Error
}

// CancelActive переводит задачу в error только если она ещё не завершена.
// Условный UPDATE защищает от гонки с завершением задачи.
func (r *ClipStore) CancelActive(ctx context.Context, id uint) (bool, error) {
	res := r.db.WithContext(ctx).Model(&models.ClipTask{}).
		Where("id = ? AND status IN ?", id, []string{models.ClipQueued, models.ClipProcessing}).
		Updates(map[string]any{"status": models.ClipError, "error": "cancelled"})
	if res.Error != nil {
		return false, res.Error
	}
	return res.RowsAffected > 0, nil
}

func (r *ClipStore) Get(ctx context.Context, id uint) (*models.ClipTask, error) {
	var task models.ClipTask
	if err := r.db.WithContext(ctx).First(&task, id).Error; err != nil {
		return nil, err
	}
	return &task, nil
}

// ListActive — незавершённые задачи без лимита истории.
func (r *ClipStore) ListActive(ctx context.Context) ([]models.ClipTask, error) {
	var tasks []models.ClipTask
	err := r.db.WithContext(ctx).
		Where("status IN ?", []string{models.ClipQueued, models.ClipProcessing}).
		Find(&tasks).Error
	return tasks, err
}

func (r *ClipStore) List(ctx context.Context) ([]models.ClipTask, error) {
	var tasks []models.ClipTask
	err := r.db.WithContext(ctx).Order("id DESC").Limit(30).Find(&tasks).Error
	return tasks, err
}
