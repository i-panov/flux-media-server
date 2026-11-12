package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

var (
	ErrDeviceCodeInvalid  = errors.New("device code invalid")
	ErrDeviceCodeExpired  = errors.New("device code expired")
	ErrDeviceCodeConsumed = errors.New("device code already used")
)

type DeviceAuthStore struct {
	db *gorm.DB
}

func NewDeviceAuthRepository(db *gorm.DB) *DeviceAuthStore {
	return &DeviceAuthStore{db: db}
}

func HashDeviceCode(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func (r *DeviceAuthStore) Create(ctx context.Context, deviceCodeHash, userCodeHash, deviceName, platform string, expiresAt time.Time, intervalSeconds int) (*models.DeviceAuth, error) {
	record := &models.DeviceAuth{
		DeviceCodeHash:  deviceCodeHash,
		UserCodeHash:    userCodeHash,
		DeviceName:      deviceName,
		Platform:        platform,
		Status:          models.DeviceAuthPending,
		ExpiresAt:       expiresAt,
		IntervalSeconds: intervalSeconds,
	}
	if err := r.db.WithContext(ctx).Create(record).Error; err != nil {
		return nil, err
	}
	return record, nil
}

func (r *DeviceAuthStore) FindByDeviceCode(ctx context.Context, hash string) (*models.DeviceAuth, error) {
	var record models.DeviceAuth
	if err := r.db.WithContext(ctx).Where("device_code_hash = ?", hash).First(&record).Error; err != nil {
		return nil, err
	}
	return &record, nil
}

// FindPendingByUserCode отдаёт только ожидающий запрос: страница
// подтверждения не должна раскрывать уже использованные/чужие коды.
func (r *DeviceAuthStore) FindPendingByUserCode(ctx context.Context, hash string) (*models.DeviceAuth, error) {
	var record models.DeviceAuth
	err := r.db.WithContext(ctx).
		Where("user_code_hash = ? AND status = ?", hash, models.DeviceAuthPending).
		First(&record).Error
	if err != nil {
		return nil, err
	}
	return &record, nil
}

// Approve атомарно переводит pending -> approved. RowsAffected==0 означает,
// что код уже подтверждён/использован/истёк гонкой.
func (r *DeviceAuthStore) Approve(ctx context.Context, userCodeHash string, userID uint) (*models.DeviceAuth, error) {
	now := time.Now()
	result := r.db.WithContext(ctx).Model(&models.DeviceAuth{}).
		Where("user_code_hash = ? AND status = ? AND expires_at > ?", userCodeHash, models.DeviceAuthPending, now).
		Updates(map[string]any{
			"status":      models.DeviceAuthApproved,
			"user_id":     userID,
			"approved_at": now,
		})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected == 0 {
		return nil, ErrDeviceCodeInvalid
	}
	var record models.DeviceAuth
	if err := r.db.WithContext(ctx).Where("user_code_hash = ?", userCodeHash).First(&record).Error; err != nil {
		return nil, err
	}
	return &record, nil
}

// Consume помечает approved-код использованным до выдачи токенов.
// Повторный poll после выдачи вернёт ErrDeviceCodeConsumed.
func (r *DeviceAuthStore) Consume(ctx context.Context, deviceCodeHash string) (*models.DeviceAuth, error) {
	now := time.Now()
	result := r.db.WithContext(ctx).Model(&models.DeviceAuth{}).
		Where("device_code_hash = ? AND status = ? AND expires_at > ?", deviceCodeHash, models.DeviceAuthApproved, now).
		Updates(map[string]any{
			"status":      models.DeviceAuthConsumed,
			"consumed_at": now,
		})
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected == 0 {
		return nil, ErrDeviceCodeConsumed
	}
	var record models.DeviceAuth
	if err := r.db.WithContext(ctx).Where("device_code_hash = ?", deviceCodeHash).First(&record).Error; err != nil {
		return nil, err
	}
	return &record, nil
}

func (r *DeviceAuthStore) DeleteExpired(ctx context.Context) error {
	return r.db.WithContext(ctx).
		Where("expires_at < ? AND status IN ?", time.Now(), []string{models.DeviceAuthPending, models.DeviceAuthApproved}).
		Delete(&models.DeviceAuth{}).Error
}
