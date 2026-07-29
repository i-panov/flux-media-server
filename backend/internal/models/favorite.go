package models

import "time"

// Favorite represents a user's liked media item or artist.
// For video/audio favorites, MediaID is set and ArtistName is NULL.
// For artist favorites, ArtistName is set and MediaID is nil.
// NULL (not empty string) is required so the composite unique indexes work:
// SQLite treats NULLs as distinct, so they never collide across rows.
type Favorite struct {
	ID         uint      `gorm:"primaryKey" json:"id"`
	UserID     uint      `gorm:"uniqueIndex:idx_user_media;uniqueIndex:idx_user_artist" json:"user_id"`
	Type       string    `gorm:"index" json:"type"` // video, audio, artist
	MediaID    *uint     `gorm:"uniqueIndex:idx_user_media" json:"media_id,omitempty"`
	ArtistName *string   `gorm:"uniqueIndex:idx_user_artist" json:"artist_name,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}
