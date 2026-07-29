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
		FileHash:     "abc123",
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
		ID:        1,
		Email:     "test@test.com",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
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

func TestFavoriteFields(t *testing.T) {
	mediaID := uint(5)
	f := Favorite{
		ID:        1,
		UserID:    1,
		Type:      "video",
		MediaID:   &mediaID,
		CreatedAt: time.Now(),
	}
	if f.ID != 1 || f.Type != "video" || *f.MediaID != 5 {
		t.Errorf("Favorite fields not properly set: %+v", f)
	}

	artist := "Pink Floyd"
	f2 := Favorite{
		ID:         2,
		UserID:     1,
		Type:       "artist",
		MediaID:    nil,
		ArtistName: &artist,
		CreatedAt:  time.Now(),
	}
	if f2.ArtistName == nil || *f2.ArtistName != "Pink Floyd" || f2.MediaID != nil {
		t.Errorf("Artist favorite fields not properly set: %+v", f2)
	}
}

func TestCollectionFields(t *testing.T) {
	c := Collection{
		ID:        1,
		UserID:    1,
		Name:      "Want to Watch",
		Type:      "video",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}
	if c.Name != "Want to Watch" || c.Type != "video" {
		t.Errorf("Collection fields not properly set: %+v", c)
	}
}

func TestCollectionItemFields(t *testing.T) {
	ci := CollectionItem{
		ID:           1,
		CollectionID: 1,
		MediaID:      5,
		AddedAt:      time.Now(),
	}
	if ci.CollectionID != 1 || ci.MediaID != 5 {
		t.Errorf("CollectionItem fields not properly set: %+v", ci)
	}
}

func TestLyricsFields(t *testing.T) {
	l := Lyrics{
		ID:          1,
		MediaID:     1,
		LyricsText:  "La la la",
		Translation: "Ля ля ля",
		SyncData:    `[{"t":0,"text":"La la la"}]`,
		Source:      "id3",
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}
	if l.MediaID != 1 || l.LyricsText != "La la la" || l.Translation != "Ля ля ля" {
		t.Errorf("Lyrics fields not properly set: %+v", l)
	}
}
