package models

import "time"

// Collection is a user-created playlist of media items (e.g. "Want to Watch").
type Collection struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index" json:"user_id"`
	Name      string    `json:"name"`
	Type      string    `gorm:"index" json:"type"` // video
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CollectionItem links a media item to a collection.
type CollectionItem struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	CollectionID uint      `gorm:"index;uniqueIndex:idx_collection_media" json:"collection_id"`
	MediaID      uint      `gorm:"index;uniqueIndex:idx_collection_media" json:"media_id"`
	Position     int       `gorm:"default:0" json:"position"`
	AddedAt      time.Time `json:"added_at"`
}
