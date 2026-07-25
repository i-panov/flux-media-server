package models

import "time"

// Favorite represents a user's liked media item or artist.
// For video/audio favorites, MediaID is set and ArtistName is empty.
// For artist favorites, ArtistName is set and MediaID is nil.
type Favorite struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"uniqueIndex:idx_user_media" json:"user_id"`
	Type       string    `gorm:"index" json:"type"` // video, audio, artist
	MediaID    *uint     `gorm:"uniqueIndex:idx_user_media" json:"media_id,omitempty"`
	ArtistName string    `gorm:"uniqueIndex:idx_user_artist" json:"artist_name,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}
