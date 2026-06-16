package models

import (
	"time"
)

type WatchProgress struct {
	ID        uint `gorm:"primaryKey"`
	UserID    uint `gorm:"index"`
	MediaID   uint `gorm:"index"`
	Position  int  // позиция в секундах
	Duration  int  // общая длительность
	Completed bool
	UpdatedAt time.Time
}
