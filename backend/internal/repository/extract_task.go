package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

// ExtractTaskStore хранит задания извлечения аудио (см. models.ExtractTask).
// In-memory очередь пишет сюда каждую смену статуса, а при старте
// поднимает незавершённые строки обратно в очередь: рестарт сервера
// больше не теряет летящие задания.
type ExtractTaskStore struct {
	db *gorm.DB
}

func NewExtractTaskRepository(db *gorm.DB) *ExtractTaskStore {
	return &ExtractTaskStore{db: db}
}

func (r *ExtractTaskStore) Create(ctx context.Context, task *models.ExtractTask) error {
	return r.db.WithContext(ctx).Create(task).Error
}

func (r *ExtractTaskStore) Get(ctx context.Context, id uint) (*models.ExtractTask, error) {
	var task models.ExtractTask
	err := r.db.WithContext(ctx).First(&task, id).Error
	return &task, err
}

// SetStatus пишет только переход статуса (+ошибку и результат): воркер
// вызывает его в точках перехода, не трогая created_at и остальное.
func (r *ExtractTaskStore) SetStatus(ctx context.Context, id uint, status, errMsg string, mediaID uint) error {
	return r.db.WithContext(ctx).Model(&models.ExtractTask{}).
		Where("id = ?", id).
		Updates(map[string]any{"status": status, "error": errMsg, "media_id": mediaID}).Error
}

func (r *ExtractTaskStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Delete(&models.ExtractTask{}, id).Error
}

// FindUnfinished возвращает незавершённые задания (queued/processing)
// по возрастанию id: именно в этом порядке они перевыставляются
// в очередь при старте.
func (r *ExtractTaskStore) FindUnfinished(ctx context.Context, active ...string) ([]models.ExtractTask, error) {
	var tasks []models.ExtractTask
	err := r.db.WithContext(ctx).Where("status IN ?", active).Order("id").Find(&tasks).Error
	return tasks, err
}

// FindActiveBySource ищет активное задание того же исходника: повторный
// POST, пока прошлый джоб летит (в т.ч. поднятый после рестарта), —
// дубль, а не второй ffmpeg на то же видео. Нет задания —
// gorm.ErrRecordNotFound.
func (r *ExtractTaskStore) FindActiveBySource(ctx context.Context, sourceID uint, active ...string) (*models.ExtractTask, error) {
	var task models.ExtractTask
	err := r.db.WithContext(ctx).
		Where("source_media_id = ? AND status IN ?", sourceID, active).
		Order("id DESC").First(&task).Error
	return &task, err
}
