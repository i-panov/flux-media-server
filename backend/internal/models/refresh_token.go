package models

import "time"

// RefreshToken stores long-lived refresh tokens for re-authentication.
type RefreshToken struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"index"`
	Token     string    `json:"-" gorm:"uniqueIndex;size:512"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}
