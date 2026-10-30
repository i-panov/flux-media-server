package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

// UploadTaskStore хранит задания загрузки (см. models.UploadTask).
// In-memory очередь пишет сюда каждую смену статуса, а при старте
// поднимает незавершённые строки обратно в очередь: рестарт сервера
// больше не теряет летящие задания.
type UploadTaskStore struct {
	db *gorm.DB
}

func NewUploadTaskRepository(db *gorm.DB) *UploadTaskStore {
	return &UploadTaskStore{db: db}
}

func (r *UploadTaskStore) Create(ctx context.Context, task *models.UploadTask) error {
	return r.db.WithContext(ctx).Create(task).Error
}

func (r *UploadTaskStore) Get(ctx context.Context, id uint64) (*models.UploadTask, error) {
	var task models.UploadTask
	err := r.db.WithContext(ctx).First(&task, id).Error
	return &task, err
}

// SetStatus пишет только переход статуса (+ошибку и результат): воркер
// вызывает его в точках перехода, не трогая created_at и остальное.
func (r *UploadTaskStore) SetStatus(ctx context.Context, id uint64, status, errMsg string, mediaID uint) error {
	return r.db.WithContext(ctx).Model(&models.UploadTask{}).
		Where("id = ?", id).
		Updates(map[string]any{"status": status, "error": errMsg, "media_id": mediaID}).Error
}

// SetFileHash фиксирует хэш файла после хэширования: по нему ловится
// повторная заливка того же контента, пока задание ещё активно.
func (r *UploadTaskStore) SetFileHash(ctx context.Context, id uint64, fileHash string) error {
	return r.db.WithContext(ctx).Model(&models.UploadTask{}).
		Where("id = ?", id).
		Update("file_hash", fileHash).Error
}

// SetDuplicate завершает задание статусом duplicate: новая запись, файл
// и превью уже удалены воркером, клиент получает id и название
// похожего мема из тех же колонок.
func (r *UploadTaskStore) SetDuplicate(ctx context.Context, id uint64, duplicateMediaID uint, duplicateTitle string) error {
	return r.db.WithContext(ctx).Model(&models.UploadTask{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"status":             "duplicate",
			"error":              "",
			"duplicate_media_id": duplicateMediaID,
			"duplicate_title":    duplicateTitle,
		}).Error
}

func (r *UploadTaskStore) Delete(ctx context.Context, id uint64) error {
	return r.db.WithContext(ctx).Delete(&models.UploadTask{}, id).Error
}

// FindUnfinished возвращает незавершённые задания (queued/processing)
// по возрастанию id: именно в этом порядке они перевыставляются
// в очередь при старте.
func (r *UploadTaskStore) FindUnfinished(ctx context.Context, active ...string) ([]models.UploadTask, error) {
	var tasks []models.UploadTask
	err := r.db.WithContext(ctx).Where("status IN ?", active).Order("id").Find(&tasks).Error
	return tasks, err
}

// FindActiveByFilePath ищет активное задание того же файла: повторный
// POST, пока прошлый джоб летит (в т.ч. поднятый после рестарта), —
// дубль, а не второе задание на тот же путь. Нет задания —
// gorm.ErrRecordNotFound.
func (r *UploadTaskStore) FindActiveByFilePath(ctx context.Context, filePath string, active ...string) (*models.UploadTask, error) {
	var task models.UploadTask
	err := r.db.WithContext(ctx).
		Where("file_path = ? AND status IN ?", filePath, active).
		Order("id DESC").First(&task).Error
	return &task, err
}

// FindActiveByHash ищет активное задание с тем же хэшем контента.
// Возвращает старейшее (ORDER BY id ASC): при параллельных заливках
// одного контента под разными именами младший дубликат завершается
// ошибкой, а старший идёт дальше (детерминированный тай-брейк по ID).
// Нет задания — gorm.ErrRecordNotFound.
func (r *UploadTaskStore) FindActiveByHash(ctx context.Context, hash string, active ...string) (*models.UploadTask, error) {
	var task models.UploadTask
	err := r.db.WithContext(ctx).
		Where("file_hash = ? AND status IN ?", hash, active).
		Order("id ASC").First(&task).Error
	return &task, err
}
