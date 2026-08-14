package models

import (
	"time"
)

type WatchProgress struct {
	ID        uint `gorm:"primaryKey" json:"id"`
	UserID    uint `gorm:"index;uniqueIndex:idx_progress_user_media" json:"user_id"`
	MediaID   uint `gorm:"index;uniqueIndex:idx_progress_user_media" json:"media_id"`
	Position  int  `json:"position"` // seconds
	Duration  int  `json:"duration"` // общая длительность в секундах (присылает клиент)
	Completed bool `json:"completed"`
	// FK-ассоциации с каскадным удалением (для новых инсталляций).
	User      *User     `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Media     *Media    `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	UpdatedAt time.Time `json:"updated_at"`
}
