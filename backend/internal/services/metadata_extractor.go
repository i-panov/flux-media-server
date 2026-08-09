package services

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/dhowden/tag"
	"gopkg.in/vansante/go-ffprobe.v2"

	"flux/internal/models"
)

// FileMetadata holds metadata extracted from a media file.
type FileMetadata struct {
	Title        string
	Artist       string
	Album        string
	Genre        string
	Year         int
	Duration     int    // seconds
	Width        int    // video only
	Height       int    // video only
	Codec        string // video only
	AlbumArt     []byte // embedded album art (audio only)
	AlbumArtMIME string
}

// MetadataExtractor extracts metadata from media files.
type MetadataExtractor struct{}

// NewMetadataExtractor creates a new MetadataExtractor.
func NewMetadataExtractor() *MetadataExtractor {
	return &MetadataExtractor{}
}

// ExtractFromFile reads metadata from a media file based on its extension.
// If probeData is provided and non-nil, it is used for video files instead of
// calling ffprobe again.
func (e *MetadataExtractor) ExtractFromFile(path string, probeData ...*ffprobe.ProbeData) *FileMetadata {
	ext := strings.ToLower(filepath.Ext(path))

	switch ext {
	case ".mp3", ".flac", ".ogg", ".m4a", ".aac", ".wav":
		return e.extractAudio(path)
	case ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".webm", ".flv", ".ts":
		if len(probeData) > 0 && probeData[0] != nil {
			return extractVideoFromData(probeData[0])
		}
		return e.extractVideo(path)
	default:
		return nil
	}
}

// extractAudio reads ID3/Vorbis/MP4 tags from an audio file.
func (e *MetadataExtractor) extractAudio(path string) *FileMetadata {
	f, err := os.Open(path)
	if err != nil {
		log.Printf("metadata: open audio file %s: %v", path, err)
		return nil
	}
	defer f.Close()

	m, err := tag.ReadFrom(f)
	if err != nil {
		log.Printf("metadata: read tags from %s: %v", path, err)
		return nil
	}

	if m == nil {
		log.Printf("metadata: tag reader returned nil metadata for %s", path)
		return nil
	}

	meta := &FileMetadata{
		Title:  m.Title(),
		Artist: m.Artist(),
		Album:  m.Album(),
		Genre:  m.Genre(),
		Year:   m.Year(),
	}

	// Extract album art if present.
	if pic := m.Picture(); pic != nil {
		meta.AlbumArt = pic.Data
		meta.AlbumArtMIME = pic.MIMEType
	}

	return meta
}

// extractVideo calls ffprobe to get video metadata.
func (e *MetadataExtractor) extractVideo(path string) *FileMetadata {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	data, err := ffprobe.ProbeURL(ctx, path)
	if err != nil {
		log.Printf("metadata: ffprobe %s: %v", path, err)
		return nil
	}

	return extractVideoFromData(data)
}

// extractVideoFromData builds FileMetadata from existing ffprobe data.
func extractVideoFromData(data *ffprobe.ProbeData) *FileMetadata {
	if data == nil {
		return nil
	}
	if data.Format == nil {
		return nil
	}

	meta := &FileMetadata{}

	if dur := data.Format.Duration(); dur > 0 {
		meta.Duration = int(dur.Seconds())
	}

	if vs := data.FirstVideoStream(); vs != nil {
		meta.Width = vs.Width
		meta.Height = vs.Height
		meta.Codec = vs.CodecName
	}

	// Some video containers store title/artist tags.
	if t, err := data.Format.TagList.GetString("title"); err == nil {
		meta.Title = t
	}
	if a, err := data.Format.TagList.GetString("artist"); err == nil {
		meta.Artist = a
	}

	return meta
}

// DetermineMediaTypeFromProbe returns the media type from probe stream data.
func DetermineMediaTypeFromProbe(data *ffprobe.ProbeData) models.MediaType {
	if data == nil {
		return models.MediaTypeVideo
	}
	hasVideo := false
	hasAudio := false
	for _, s := range data.Streams {
		switch s.CodecType {
		case "video":
			// Skip embedded cover art (mjpeg, png, jpeg, bmp, ...) — it is
			// not real video. Audio files with embedded covers must be
			// classified as audio.
			codec := strings.ToLower(s.CodecName)
			if codec == "mjpeg" || codec == "png" || codec == "jpegls" ||
				codec == "bmp" || codec == "gif" || codec == "tiff" {
				continue
			}
			hasVideo = true
		case "audio":
			hasAudio = true
		}
	}
	if hasAudio && !hasVideo {
		return models.MediaTypeAudio
	}
	return models.MediaTypeVideo
}
