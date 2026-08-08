package models

import "time"

// Artist represents a music artist or creator.
type Artist struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"uniqueIndex;size:255" json:"name"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// MediaArtist is the join table between Media and Artist with a position
// for ordering artists on a track.
type MediaArtist struct {
	MediaID  uint `gorm:"primaryKey;uniqueIndex:idx_media_artist_pair" json:"media_id"`
	ArtistID uint `gorm:"primaryKey;uniqueIndex:idx_media_artist_pair" json:"artist_id"`
	Position int  `gorm:"default:0" json:"position"`
}
