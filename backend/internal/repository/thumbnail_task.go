package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type ThumbnailStore struct {
	db *gorm.DB
}

func NewThumbnailRepository(db *gorm.DB) *ThumbnailStore {
	return &ThumbnailStore{db: db}
}

func (r *ThumbnailStore) Enqueue(ctx context.Context, mediaID uint, kind string) error {
	task := models.ThumbnailTask{
		MediaID: mediaID, Kind: kind, Status: models.ThumbnailTaskQueued,
	}
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).
		Create(&task).Error
}

// ResetFinished убирает завершённые задачи, чтобы повторный запуск снова
// поставил их в очередь.
func (r *ThumbnailStore) ResetFinished(ctx context.Context, kind string) error {
	return r.db.WithContext(ctx).Where("kind = ? AND status IN ?", kind,
		[]string{models.ThumbnailTaskDone, models.ThumbnailTaskError}).
		Delete(&models.ThumbnailTask{}).Error
}

func (r *ThumbnailStore) NextQueued(ctx context.Context) (*models.ThumbnailTask, error) {
	var task models.ThumbnailTask
	err := r.db.WithContext(ctx).
		Where("status = ?", models.ThumbnailTaskQueued).
		Order("id").First(&task).Error
	if err != nil {
		return nil, err
	}
	res := r.db.WithContext(ctx).Model(&models.ThumbnailTask{}).
		Where("id = ? AND status = ?", task.ID, models.ThumbnailTaskQueued).
		Updates(map[string]any{
			"status":   models.ThumbnailTaskProcessing,
			"attempts": task.Attempts + 1,
		})
	if res.Error != nil {
		return nil, res.Error
	}
	if res.RowsAffected == 0 {
		return nil, gorm.ErrRecordNotFound
	}
	task.Status = models.ThumbnailTaskProcessing
	task.Attempts++
	return &task, nil
}

func (r *ThumbnailStore) Finish(ctx context.Context, id uint, status, message string) error {
	return r.db.WithContext(ctx).Model(&models.ThumbnailTask{}).
		Where("id = ?", id).
		Updates(map[string]any{"status": status, "error": message}).Error
}

func (r *ThumbnailStore) Pending(ctx context.Context, kind string) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&models.ThumbnailTask{}).
		Where("kind = ? AND status IN ?", kind,
			[]string{models.ThumbnailTaskQueued, models.ThumbnailTaskProcessing}).
		Count(&count).Error
	return count, err
}
