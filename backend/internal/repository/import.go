package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type ImportStore struct {
	db *gorm.DB
}

func NewImportRepository(db *gorm.DB) *ImportStore {
	return &ImportStore{db: db}
}

func (r *ImportStore) Create(ctx context.Context, job *models.ImportJob, episodes []models.ImportEpisode) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(job).Error; err != nil {
			return err
		}
		for i := range episodes {
			episodes[i].ImportID = job.ID
			if err := tx.Create(&episodes[i]).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *ImportStore) Update(ctx context.Context, id uint, updates map[string]any) error {
	return r.db.WithContext(ctx).Model(&models.ImportJob{}).Where("id = ?", id).
		Updates(updates).Error
}

func (r *ImportStore) Get(ctx context.Context, id uint) (*models.ImportJob, []models.ImportEpisode, error) {
	var job models.ImportJob
	if err := r.db.WithContext(ctx).First(&job, id).Error; err != nil {
		return nil, nil, err
	}
	var episodes []models.ImportEpisode
	if err := r.db.WithContext(ctx).Where("import_id = ?", id).
		Order("season ASC, episode ASC").Find(&episodes).Error; err != nil {
		return nil, nil, err
	}
	return &job, episodes, nil
}

func (r *ImportStore) UpdateEpisode(ctx context.Context, id uint, updates map[string]any) error {
	return r.db.WithContext(ctx).Model(&models.ImportEpisode{}).Where("id = ?", id).
		Updates(updates).Error
}

// ListActive — все незавершённые задания без лимита: восстановление
// после рестарта не должно зависеть от длины истории.
func (r *ImportStore) ListActive(ctx context.Context) ([]models.ImportJob, error) {
	var jobs []models.ImportJob
	err := r.db.WithContext(ctx).
		Where("status IN ?", []string{models.ImportQueued, models.ImportDownloading, models.ImportImporting}).
		Find(&jobs).Error
	return jobs, err
}

func (r *ImportStore) List(ctx context.Context) ([]models.ImportJob, error) {
	var jobs []models.ImportJob
	err := r.db.WithContext(ctx).Order("id DESC").Limit(30).Find(&jobs).Error
	return jobs, err
}
