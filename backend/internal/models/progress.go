package models

import (
	"time"
)

type WatchProgress struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// Одиночный индекс по user_id не нужен: композитный uniqueIndex по
	// (user_id, media_id) и композитный index по (user_id, updated_at)
	// покрывают все запросы (список прогресса пользователя, сортировка
	// по недавно просмотренному).
	UserID    uint `gorm:"uniqueIndex:idx_progress_user_media;index:idx_progress_user_updated,priority:1" json:"user_id"`
	MediaID   uint `gorm:"uniqueIndex:idx_progress_user_media" json:"media_id"`
	Position  int  `json:"position"` // seconds
	Duration  int  `json:"duration"` // общая длительность в секундах (присылает клиент)
	Completed bool `json:"completed"`
	// FK-ассоциации с каскадным удалением (для новых инсталляций).
	User      *User     `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Media     *Media    `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	UpdatedAt time.Time `gorm:"index:idx_progress_user_updated,priority:2" json:"updated_at"`
}
