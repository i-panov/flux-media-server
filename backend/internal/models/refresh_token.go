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
	// FK-ассоциация с каскадным удалением (для новых инсталляций).
	User *User `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
}
