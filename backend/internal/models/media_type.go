package models

import (
	"database/sql/driver"
	"fmt"
	"strings"
)

// MediaType represents a media type: video or audio.
type MediaType string

const (
	MediaTypeVideo MediaType = "video"
	MediaTypeAudio MediaType = "audio"
)

func (mt MediaType) Valid() bool {
	return mt == MediaTypeVideo || mt == MediaTypeAudio
}

// Scan implements sql.Scanner so that MediaType can be used as a gorm datatype.
func (mt *MediaType) Scan(value interface{}) error {
	if value == nil {
		return nil
	}
	s, ok := value.(string)
	if !ok {
		return fmt.Errorf("MediaType.Scan: cannot convert %T to string", value)
	}
	*mt = MediaType(s)
	return nil
}

// Value implements driver.Valuer so that MediaType can be written to a database.
func (mt MediaType) Value() (driver.Value, error) {
	if mt == "" {
		return nil, nil
	}
	return string(mt), nil
}

// IsVideo returns true if the type is video.
func (mt MediaType) IsVideo() bool { return mt == MediaTypeVideo }

// IsAudio returns true if the type is audio.
func (mt MediaType) IsAudio() bool { return mt == MediaTypeAudio }

// ParseMediaType returns the MediaType for the given string, or empty string if invalid.
func ParseMediaType(s string) MediaType {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "video":
		return MediaTypeVideo
	case "audio":
		return MediaTypeAudio
	default:
		return ""
	}
}
