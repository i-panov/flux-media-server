package models

import (
	"time"
)

type MediaLibrary struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `json:"name"`
	Path         string    `gorm:"uniqueIndex" json:"-"`
	Type         string    `json:"type"` // "video" or "audio"
	Enabled      bool      `json:"enabled"`
	ScanInterval int       `json:"scan_interval"` // minutes, 0 = disabled
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
