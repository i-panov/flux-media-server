package models

import (
	"testing"
	"time"
)

func TestMediaFields(t *testing.T) {
	m := Media{
		ID:           1,
		Title:        "Test",
		Year:         2024,
		Description:  "desc",
		Type:         "movie",
		Duration:     3600,
		FilePath:     "/test.mkv",
		FileSize:     1024,
		ThumbnailURL: "http://thumb",
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	if m.ID != 1 || m.Title != "Test" || m.Type != "movie" {
		t.Errorf("Media fields not properly set: %+v", m)
	}
}

func TestMetadataFields(t *testing.T) {
	m := Metadata{
		ID:         1,
		ExternalID: "tmdb-123",
		Source:     "tmdb",
		Title:      "Test",
		Rating:     8.5,
		Genres:     `["action"]`,
		Cast:       `["actor1"]`,
		CreatedAt:  time.Now(),
	}
	if m.ExternalID != "tmdb-123" || m.Source != "tmdb" {
		t.Errorf("Metadata fields not properly set: %+v", m)
	}
}

func TestUserFields(t *testing.T) {
	u := User{
		ID:          1,
		Email:       "test@test.com",
		DisplayName: "Test User",
		AvatarURL:   "http://avatar",
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
	if u.Email != "test@test.com" {
		t.Errorf("User fields not properly set: %+v", u)
	}
}

func TestWatchProgressFields(t *testing.T) {
	wp := WatchProgress{
		ID:        1,
		UserID:    1,
		MediaID:   1,
		Position:  1800,
		Duration:  3600,
		Completed: false,
		UpdatedAt: time.Now(),
	}
	if wp.Position != 1800 || wp.Completed != false {
		t.Errorf("WatchProgress fields not properly set: %+v", wp)
	}
}

func TestMediaLibraryFields(t *testing.T) {
	ml := MediaLibrary{
		ID:           1,
		Name:         "Movies",
		Path:         "/movies",
		Type:         "movie",
		Enabled:      true,
		ScanInterval: 60,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
	if ml.Path != "/movies" || ml.ScanInterval != 60 {
		t.Errorf("MediaLibrary fields not properly set: %+v", ml)
	}
}
