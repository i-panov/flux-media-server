package models

import "time"

// Lyrics holds optional lyrics text, translation, and sync timestamps for a media item.
type Lyrics struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	MediaID     uint      `gorm:"uniqueIndex" json:"media_id"`
	LyricsText  string    `gorm:"type:text" json:"lyrics_text"`
	Translation string    `gorm:"type:text" json:"translation"`
	SyncData    string    `gorm:"type:text" json:"sync_data"` // JSON array of {timestamp, text} pairs
	Source      string    `json:"source"`                      // id3, manual, external
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
