package models

import "time"

// Lyrics holds optional lyrics text, translation, and sync timestamps for a media item.
type Lyrics struct {
	ID          uint   `gorm:"primaryKey" json:"id"`
	MediaID     uint   `gorm:"uniqueIndex" json:"media_id"`
	LyricsText  string `gorm:"type:text" json:"lyrics_text"`
	Translation string `gorm:"type:text" json:"translation"`
	SyncData    string `gorm:"type:text" json:"sync_data"` // JSON array of {timestamp, text} pairs
	Source      string `gorm:"size:255" json:"source"`     // id3, manual, external
	// FK-ассоциация с каскадным удалением (для новых инсталляций).
	Media     *Media    `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
