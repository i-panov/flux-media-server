package repository

import (
	"context"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

type TranscodeTaskStore struct {
	db *gorm.DB
}

func NewTranscodeTaskRepository(db *gorm.DB) *TranscodeTaskStore {
	return &TranscodeTaskStore{db: db}
}

func (r *TranscodeTaskStore) Create(ctx context.Context, task *models.TranscodeTask) error {
	return r.db.WithContext(ctx).Create(task).Error
}

func (r *TranscodeTaskStore) Get(ctx context.Context, id uint) (*models.TranscodeTask, error) {
	var task models.TranscodeTask
	err := r.db.WithContext(ctx).First(&task, id).Error
	return &task, err
}

// Update сохраняет задание целиком: воркер — единственный писатель
// строки (по одному заданию одновременно работает только он),
// поэтому blind-save без оптимистичных версий достаточен.
func (r *TranscodeTaskStore) Update(ctx context.Context, task *models.TranscodeTask) error {
	return r.db.WithContext(ctx).Save(task).Error
}

// UpdateIfStatus сохраняет задание, только если его текущий статус
// входит в allowed. Нужно воркеру: отмена (cancelled) и финал (done)
// не должны перезаписываться поздними прогресс-записями — иначе
// отменённое задание воскреснет. Возвращает, была ли запись.
//
// Реализация — Select("*").Updates, а НЕ Save: Save при нуле затронутых
// строк падает в CREATE ... ON CONFLICT UPDATE и молча перезаписывает
// строку безусловно. Select("*") пишет и нулевые поля (Progress=0,
// MediaID=0 значимы), fallback'а на Create у Updates нет.
func (r *TranscodeTaskStore) UpdateIfStatus(ctx context.Context, task *models.TranscodeTask, allowed ...string) (bool, error) {
	res := r.db.WithContext(ctx).Where("id = ? AND status IN ?", task.ID, allowed).Select("*").Updates(task)
	return res.RowsAffected > 0, res.Error
}

// FindLatestBySourcePath возвращает последнее задание для исходника
// (порядок по id). Нет заданий — gorm.ErrRecordNotFound.
func (r *TranscodeTaskStore) FindLatestBySourcePath(ctx context.Context, sourcePath string) (*models.TranscodeTask, error) {
	var task models.TranscodeTask
	err := r.db.WithContext(ctx).Where("source_path = ?", sourcePath).Order("id DESC").First(&task).Error
	return &task, err
}

// FindActiveBySourceHash ищет активное (queued/processing) задание с тем
// же хэшем исходника: повторная заливка во время обработки — дубль,
// а не вторая нормализация того же файла.
func (r *TranscodeTaskStore) FindActiveBySourceHash(ctx context.Context, hash string, active ...string) (*models.TranscodeTask, error) {
	var task models.TranscodeTask
	err := r.db.WithContext(ctx).Where("source_hash = ? AND status IN ?", hash, active).Order("id DESC").First(&task).Error
	return &task, err
}

// ClaimNextQueued атомарно забирает старейшее queued-задание:
// UPDATE ... WHERE status=queued, RowsAffected — признак выигрыша.
// Воркер один, но защита нужна и от двойного срабатывания (wake + poll).
func (r *TranscodeTaskStore) ClaimNextQueued(ctx context.Context, queued, processing string) (*models.TranscodeTask, error) {
	var task models.TranscodeTask
	if err := r.db.WithContext(ctx).Where("status = ?", queued).Order("id").First(&task).Error; err != nil {
		return nil, err
	}
	res := r.db.WithContext(ctx).Model(&models.TranscodeTask{}).
		Where("id = ? AND status = ?", task.ID, queued).
		Update("status", processing)
	if res.Error != nil {
		return nil, res.Error
	}
	if res.RowsAffected == 0 {
		return nil, gorm.ErrRecordNotFound
	}
	task.Status = processing
	return &task, nil
}

// ResetStuckProcessing возвращает «подвисшие» processing-задания обратно
// в queued: только этот процесс пишет строки, значит processing при
// старте — след упавшего воркера. Возвращает число затронутых строк.
func (r *TranscodeTaskStore) ResetStuckProcessing(ctx context.Context, processing, queued string) (int64, error) {
	res := r.db.WithContext(ctx).Model(&models.TranscodeTask{}).
		Where("status = ?", processing).
		Updates(map[string]interface{}{"status": queued})
	return res.RowsAffected, res.Error
}

// DeleteTerminalBefore удаляет терминальные (done/error/cancelled)
// задания старше порога: история нужна админке, но не бесконечно.
// Возвращает число удалённых строк.
func (r *TranscodeTaskStore) DeleteTerminalBefore(ctx context.Context, before time.Time, terminal ...string) (int64, error) {
	res := r.db.WithContext(ctx).Where("status IN ? AND updated_at < ?", terminal, before).
		Delete(&models.TranscodeTask{})
	return res.RowsAffected, res.Error
}

// ListTerminalBefore возвращает терминальные задания старше порога
// (для выборочной чистки с проверкой файлов). Keyset-пагинация по id:
// afterID — последний ID прошлой страницы, limit <= 0 — без лимита.
func (r *TranscodeTaskStore) ListTerminalBefore(ctx context.Context, before time.Time, afterID uint, limit int, terminal ...string) ([]models.TranscodeTask, error) {
	var tasks []models.TranscodeTask
	q := r.db.WithContext(ctx).Where("status IN ? AND updated_at < ? AND id > ?", terminal, before, afterID).Order("id")
	if limit > 0 {
		q = q.Limit(limit)
	}
	return tasks, q.Find(&tasks).Error
}

// DeleteByIDs удаляет задания по списку ID. Пустой список — no-op.
func (r *TranscodeTaskStore) DeleteByIDs(ctx context.Context, ids []uint) error {
	if len(ids) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Where("id IN ?", ids).Delete(&models.TranscodeTask{}).Error
}

// ListRecent возвращает последние задания для админки.
func (r *TranscodeTaskStore) ListRecent(ctx context.Context, limit int) ([]models.TranscodeTask, error) {
	var tasks []models.TranscodeTask
	q := r.db.WithContext(ctx).Order("id DESC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	return tasks, q.Find(&tasks).Error
}
