package models

import (
	"time"
)

type User struct {
	ID          uint      `gorm:"primaryKey"`
	Email       string    `gorm:"uniqueIndex"`
	DisplayName string
	AvatarURL   string
	CreatedAt   time.Time
	UpdatedAt   time.Time
}
