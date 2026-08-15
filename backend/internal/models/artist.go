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
// for ordering artists on a track. Уникальность пары (media_id, artist_id)
// обеспечивается составным первичным ключом, отдельный uniqueIndex не нужен.
type MediaArtist struct {
	MediaID  uint `gorm:"primaryKey" json:"media_id"`
	ArtistID uint `gorm:"primaryKey" json:"artist_id"`
	Position int  `gorm:"default:0" json:"position"`
}

// ArtistLink is a row from media_artists JOIN artists, used by the
// repository to attach artists to media in the correct position order
// without GORM's many2many preload (which cannot ORDER BY a join-table
// column and would require a manual JOIN that causes duplicate artists
// via a cartesian product across all media_artists rows of each artist).
type ArtistLink struct {
	MediaID  uint   `gorm:"column:media_id"`
	ArtistID uint   `gorm:"column:artist_id"`
	Name     string `gorm:"column:name"`
	Position int    `gorm:"column:position"`
}
