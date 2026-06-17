package models

import (
	"time"
)

type Media struct {
	ID           uint      `gorm:"primaryKey"`
	Title        string    `gorm:"index"`
	Year         int
	Description  string
	Type         string    `gorm:"index"` // movie, episode
	Duration     int       // в секундах
	FilePath     string    `gorm:"uniqueIndex"`
	FileSize     int64
	FileHash     string    `gorm:"index"`
	ThumbnailURL string
	MetadataID   *uint
	Metadata     *Metadata
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type Metadata struct {
	ID          uint   `gorm:"primaryKey"`
	ExternalID  string `gorm:"uniqueIndex"`
	Source      string // tmdb, tvdb
	Title       string
	Year        int
	Description string
	PosterURL   string
	BackdropURL string
	Rating      float64
	Genres      string // JSON array
	Cast        string // JSON array
	CreatedAt   time.Time
}
