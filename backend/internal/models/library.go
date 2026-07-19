package models

import (
	"time"
)

type MediaLibrary struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Name         string    `json:"name"`
	Path         string    `gorm:"uniqueIndex" json:"path"`
	Type         string    `json:"type"` // movie, tv
	Enabled      bool      `json:"enabled"`
	ScanInterval int       `json:"scan_interval"` // в минутах, 0 = отключено
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}
