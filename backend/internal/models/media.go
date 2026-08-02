package models

import (
	"time"

	"gorm.io/gorm"
)

type Media struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	LibraryID    uint           `gorm:"not null;index;constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"library_id"`
	Title        string         `gorm:"index" json:"title"`
	Filename     string         `gorm:"index" json:"filename"`
	Year         int            `json:"year"`
	Description  string         `gorm:"index" json:"description"`
	Type         string         `gorm:"index" json:"type"` // movie, episode, audio
	Artist       string         `gorm:"index" json:"artist"`
	Album        string         `gorm:"index" json:"album"`
	Genre        string         `json:"genre"`
	Duration     int            `json:"duration"` // seconds
	FilePath     string         `gorm:"uniqueIndex" json:"-"`
	FileSize     int64          `json:"file_size"`
	FileHash     string         `gorm:"index" json:"file_hash"`
	QuickHash    string         `gorm:"index" json:"quick_hash"`
	ThumbnailURL string         `json:"thumbnail_url"`
	CoverURL     string         `json:"cover_url"`
	MetadataID   *uint          `json:"metadata_id,omitempty"`
	Metadata     *Metadata      `json:"metadata,omitempty"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

type Metadata struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// ExternalID is the ID in the external source (tmdb, ...). It is a plain
	// index (not unique): manually edited metadata has no external ID and
	// would otherwise collide on the empty value.
	ExternalID  string    `gorm:"index" json:"external_id"`
	Source      string    `json:"source"` // tmdb, tvdb
	Title       string    `json:"title"`
	Year        int       `json:"year"`
	Description string    `json:"description"`
	PosterURL   string    `json:"poster_url"`
	BackdropURL string    `json:"backdrop_url"`
	Rating      float64   `json:"rating"`
	Genres      string    `json:"genres"` // JSON array
	Cast        string    `json:"cast"`   // JSON array
	CreatedAt   time.Time `json:"created_at"`
}
