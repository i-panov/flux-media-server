package models

import (
	"time"
)

type Media struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Title        string    `gorm:"index" json:"title"`
	Year         int       `json:"year"`
	Description  string    `json:"description"`
	Type         string    `gorm:"index" json:"type"` // movie, episode, audio
	Artist       string    `gorm:"index" json:"artist"`
	Album        string    `json:"album"`
	Genre        string    `json:"genre"`
	Duration     int       `json:"duration"` // seconds
	FilePath     string    `gorm:"uniqueIndex" json:"file_path"`
	FileSize     int64     `json:"file_size"`
	FileHash     string    `gorm:"index" json:"file_hash"`
	QuickHash    string    `gorm:"index" json:"quick_hash"`
	ThumbnailURL string    `json:"thumbnail_url"`
	MetadataID   *uint     `json:"metadata_id,omitempty"`
	Metadata     *Metadata `json:"metadata,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type Metadata struct {
	ID          uint    `gorm:"primaryKey" json:"id"`
	ExternalID  string  `gorm:"uniqueIndex" json:"external_id"`
	Source      string  `json:"source"` // tmdb, tvdb
	Title       string  `json:"title"`
	Year        int     `json:"year"`
	Description string  `json:"description"`
	PosterURL   string  `json:"poster_url"`
	BackdropURL string  `json:"backdrop_url"`
	Rating      float64 `json:"rating"`
	Genres      string  `json:"genres"` // JSON array
	Cast        string  `json:"cast"`   // JSON array
	CreatedAt   time.Time `json:"created_at"`
}
