package models

import (
	"time"
)

type WatchProgress struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index;idx_user_media,unique" json:"user_id"`
	MediaID   uint      `gorm:"index;idx_user_media,unique" json:"media_id"`
	Position  int       `json:"position"`   // позиция в секундах
	Duration  int       `json:"duration"`   // общая длительность
	Completed bool      `json:"completed"`
	UpdatedAt time.Time `json:"updated_at"`
}
