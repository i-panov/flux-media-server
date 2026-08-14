package models

import "time"

// Favorite represents a user's liked media item or artist.
// For media favorites, MediaID is set and ArtistID is NULL.
// For artist favorites, ArtistID is set and MediaID is nil.
// NULL (not empty string) is required so the composite unique indexes work:
// SQLite treats NULLs as distinct, so they never collide across rows.
type Favorite struct {
	ID       uint  `gorm:"primaryKey" json:"id"`
	UserID   uint  `gorm:"uniqueIndex:idx_user_media;uniqueIndex:idx_user_artist" json:"user_id"`
	MediaID  *uint `gorm:"uniqueIndex:idx_user_media" json:"media_id,omitempty"`
	ArtistID *uint `gorm:"uniqueIndex:idx_user_artist" json:"artist_id,omitempty"`
	// FK-ассоциации: для новых инсталляций создаются внешние ключи с
	// каскадным удалением. Для существующих таблиц SQLite AutoMigrate
	// constraint не добавит — это defense in depth, ручные каскады в
	// репозиториях остаются фоллбэком.
	User      *User     `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Media     *Media    `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"media,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}
