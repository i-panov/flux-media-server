package models

import (
	"time"

	"gorm.io/gorm"
)

type Media struct {
	ID           uint           `gorm:"primaryKey" json:"id"`
	Title        string         `gorm:"index" json:"title"`
	Filename     string         `gorm:"index" json:"filename"`
	Year         int            `json:"year"`
	Description  string         `gorm:"index" json:"description"`
	Type         MediaType      `gorm:"index;type:text" json:"type"` // video, audio
	Artists      []Artist       `gorm:"many2many:media_artists;" json:"artists"`
	Album        string         `gorm:"index" json:"album"`
	Genre        string         `json:"genre"`
	Duration     int            `json:"duration"` // seconds
	// FilePath is indexed (not unique): a unique index conflicts with soft
	// delete — a file re-appearing after its record was soft-deleted would
	// fail with a UNIQUE error and the media would be lost. Duplicate
	// detection is done in the scanner via FindByPath/FindByHash.
	FilePath string `gorm:"index" json:"-"`
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
