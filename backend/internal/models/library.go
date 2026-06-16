package models

import (
	"time"
)

type MediaLibrary struct {
	ID           uint   `gorm:"primaryKey"`
	Name         string
	Path         string `gorm:"uniqueIndex"`
	Type         string // movie, tv
	Enabled      bool
	ScanInterval int    // в минутах, 0 = отключено
	CreatedAt    time.Time
	UpdatedAt    time.Time
}
