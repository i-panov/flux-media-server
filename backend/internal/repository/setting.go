package repository

import (
	"context"
	"errors"
	"strconv"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// SettingAutoCleanupOriginals — ключ настройки авточистки карантина
// оригиналов. Значение перекрывает storage.auto_cleanup_originals из YAML:
// админка меняет его без рестарта, конфиг остаётся fallback'ом.
const SettingAutoCleanupOriginals = "storage.auto_cleanup_originals"

// SettingStore хранит настройки инстанса в таблице settings.
type SettingStore struct {
	db *gorm.DB
}

func NewSettingRepository(db *gorm.DB) *SettingStore {
	return &SettingStore{db: db}
}

// Get возвращает значение ключа; ok=false, если ключа ещё нет.
func (r *SettingStore) Get(ctx context.Context, key string) (string, bool, error) {
	var setting models.Setting
	err := r.db.WithContext(ctx).Where("key = ?", key).First(&setting).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return "", false, nil
		}
		return "", false, err
	}
	return setting.Value, true, nil
}

// Set создаёт ключ или перезаписывает значение (upsert по primary key).
func (r *SettingStore) Set(ctx context.Context, key, value string) error {
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "key"}},
		DoUpdates: clause.AssignmentColumns([]string{"value", "updated_at"}),
	}).Create(&models.Setting{Key: key, Value: value, UpdatedAt: time.Now()}).Error
}

// GetBool читает булеву настройку. Повреждённое значение трактуется как
// отсутствие настройки (ok=false), чтобы вызывающий взял fallback из конфига.
func (r *SettingStore) GetBool(ctx context.Context, key string) (bool, bool, error) {
	raw, ok, err := r.Get(ctx, key)
	if err != nil || !ok {
		return false, false, err
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		// Битая настройка трактуется как «не задана»: сервер продолжает
		// работать на дефолте, а не падает из-за ручной правки в БД.
		return false, false, nil //nolint:nilerr
	}
	return value, true, nil
}

func (r *SettingStore) SetBool(ctx context.Context, key string, value bool) error {
	return r.Set(ctx, key, strconv.FormatBool(value))
}
