package models

import (
	"time"
)

type User struct {
	ID        uint      `gorm:"primaryKey"`
	Email     string    `gorm:"uniqueIndex"`
	CreatedAt time.Time
	UpdatedAt time.Time
}
