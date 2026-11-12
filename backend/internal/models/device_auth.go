package models

import "time"

const (
	DeviceAuthPending  = "pending"
	DeviceAuthApproved = "approved"
	DeviceAuthConsumed = "consumed"
	DeviceAuthDenied   = "denied"
)

// DeviceAuth — одноразовый запрос входа на устройстве без клавиатуры.
// Наружу отдаются только сырые device_code/user_code; в БД лежат их
// SHA-256-хеши, поэтому утечка базы не даёт завершить чужой вход.
type DeviceAuth struct {
	ID              uint       `json:"id" gorm:"primaryKey"`
	DeviceCodeHash  string     `json:"-" gorm:"uniqueIndex;size:64"`
	UserCodeHash    string     `json:"-" gorm:"uniqueIndex;size:64"`
	DeviceName      string     `json:"device_name" gorm:"size:120"`
	Platform        string     `json:"platform" gorm:"size:32"`
	Status          string     `json:"status" gorm:"index;size:16"`
	UserID          *uint      `json:"user_id,omitempty" gorm:"index"`
	ExpiresAt       time.Time  `json:"expires_at" gorm:"index"`
	IntervalSeconds int        `json:"interval_seconds"`
	ApprovedAt      *time.Time `json:"approved_at,omitempty"`
	ConsumedAt      *time.Time `json:"consumed_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	User            *User      `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
}
