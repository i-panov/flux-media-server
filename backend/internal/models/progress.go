package models

import (
	"time"
)

type WatchProgress struct {
	ID        uint `gorm:"primaryKey"`
	UserID    uint `gorm:"index;idx_user_media,unique"`
	MediaID   uint `gorm:"index;idx_user_media,unique"`
	Position  int  // позиция в секундах
	Duration  int  // общая длительность
	Completed bool
	UpdatedAt time.Time
}
