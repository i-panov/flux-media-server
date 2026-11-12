package models

import "time"

// RefreshToken stores long-lived refresh tokens for re-authentication.
type RefreshToken struct {
	ID     uint   `json:"id" gorm:"primaryKey"`
	UserID uint   `json:"user_id" gorm:"index"`
	Token  string `json:"-" gorm:"uniqueIndex;size:512"`
	// ExpiresAt индексируется для быстрого DeleteExpired.
	ExpiresAt time.Time `json:"expires_at" gorm:"index"`
	CreatedAt time.Time `json:"created_at"`
	// Метаданные устройства нужны для списка сессий и отзыва. Пустые
	// значения у старых токенов трактуются как неизвестное устройство.
	DeviceID   string     `json:"device_id" gorm:"index;size:64"`
	DeviceName string     `json:"device_name" gorm:"size:120"`
	Platform   string     `json:"platform" gorm:"size:32"`
	LastUsedAt *time.Time `json:"last_used_at"`
	// FK-ассоциация с каскадным удалением (для новых инсталляций).
	User *User `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
}
