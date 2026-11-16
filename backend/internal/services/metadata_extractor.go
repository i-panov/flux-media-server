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
	Title       string
	Artist      string
	Album       string
	Genre       string
	Year        int
	Description string
	AlbumArtist string
	Composer    string
	TrackNumber int
	DiscNumber  int
	Duration    int    // seconds
	Width       int    // video only
	Height      int    // video only
	Codec       string // video only
}

// MetadataExtractor extracts metadata from media files.
type MetadataExtractor struct{}

// NewMetadataExtractor creates a new MetadataExtractor.
func NewMetadataExtractor() *MetadataExtractor {
	return &MetadataExtractor{}
}

// ExtractFromFile reads metadata from a media file based on its extension.
// If probeData is provided and non-nil, it is used for video files instead of
// calling ffprobe again. Без контекста — для внешних вызовов (upload handler).
func (e *MetadataExtractor) ExtractFromFile(path string, probeData ...*ffprobe.ProbeData) *FileMetadata {
	return e.ExtractFromFileContext(context.Background(), path, probeData...)
}

// ExtractFromFileContext — то же, что ExtractFromFile, но с учётом отмены
// контекста: ffprobe и чтение файла прерываются при отмене скана.
func (e *MetadataExtractor) ExtractFromFileContext(ctx context.Context, path string, probeData ...*ffprobe.ProbeData) *FileMetadata {
	ext := strings.ToLower(filepath.Ext(path))

	switch {
	case audioExtensions[ext]:
		meta := e.extractAudio(ctx, path)
		if meta == nil {
			meta = &FileMetadata{}
		}
		// ID3/Vorbis не содержат длительности. В сканере проба уже есть;
		// для upload/внешних вызовов без неё делаем отдельный ffprobe.
		if len(probeData) > 0 && probeData[0] != nil && probeData[0].Format != nil {
			if dur := probeData[0].Format.Duration(); dur > 0 {
				meta.Duration = int(dur.Seconds())
			}
		} else if meta.Duration == 0 {
			if dur := e.probeDuration(ctx, path); dur > 0 {
				meta.Duration = dur
			}
		}
		return meta
	case videoExtensions[ext], imageExtensions[ext]:
		// Картинкам из пробы нужны только Width/Height — их отдаёт тот
		// же поток, что и у видео. Длительность у картинки нулевая.
		if len(probeData) > 0 && probeData[0] != nil {
			return extractVideoFromData(probeData[0])
		}
		return e.extractVideo(ctx, path)
	default:
		return nil
	}
}

// extractAudio reads ID3/Vorbis/MP4 tags from an audio file.
func (e *MetadataExtractor) extractAudio(ctx context.Context, path string) *FileMetadata {
	if err := ctx.Err(); err != nil {
		return nil
	}
	// #nosec G304 -- путь из библиотеки/карантина, проверен вызывающим.
	f, err := os.Open(path)
	if err != nil {
		log.Printf("metadata: open audio file %s: %v", path, err)
		return nil
	}
	defer f.Close()

	m, err := tag.ReadFrom(contextReadSeeker{contextReader{ctx: ctx, r: f}})
	if err != nil {
		log.Printf("metadata: read tags from %s: %v", path, err)
		return nil
	}

	if m == nil {
		log.Printf("metadata: tag reader returned nil metadata for %s", path)
		return nil
	}

	track, _ := m.Track()
	disc, _ := m.Disc()
	return &FileMetadata{
		Title:       m.Title(),
		Artist:      m.Artist(),
		Album:       m.Album(),
		Genre:       m.Genre(),
		Year:        m.Year(),
		Description: m.Comment(),
		AlbumArtist: m.AlbumArtist(),
		Composer:    m.Composer(),
		TrackNumber: track,
		DiscNumber:  disc,
	}
}

// extractVideo calls ffprobe to get video metadata.
func (e *MetadataExtractor) extractVideo(ctx context.Context, path string) *FileMetadata {
	probeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	data, err := ffprobe.ProbeURL(probeCtx, path)
	if err != nil {
		log.Printf("metadata: ffprobe %s: %v", path, err)
		return nil
	}

	return extractVideoFromData(data)
}

// probeDuration — ffprobe только за длительностью. Нужен аудио при
// вызовах без готовой probeData (upload, backfill старых записей).
func (e *MetadataExtractor) probeDuration(ctx context.Context, path string) int {
	probeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	data, err := ffprobe.ProbeURL(probeCtx, path)
	if err != nil || data == nil || data.Format == nil {
		return 0
	}
	if dur := data.Format.Duration(); dur > 0 {
		return int(dur.Seconds())
	}
	return 0
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

	// Some video containers store title/artist/genre/date tags.
	if t, err := data.Format.TagList.GetString("title"); err == nil {
		meta.Title = t
	}
	if a, err := data.Format.TagList.GetString("artist"); err == nil {
		meta.Artist = a
	}
	if album, err := data.Format.TagList.GetString("album"); err == nil {
		meta.Album = album
	}
	if genre, err := data.Format.TagList.GetString("genre"); err == nil {
		meta.Genre = genre
	}
	if comment, err := data.Format.TagList.GetString("comment"); err == nil {
		meta.Description = comment
	}
	if date, err := data.Format.TagList.GetString("date"); err == nil {
		meta.Year = parseTagYear(date)
	}
	if meta.Year == 0 {
		if year, err := data.Format.TagList.GetString("year"); err == nil {
			meta.Year = parseTagYear(year)
		}
	}

	return meta
}

func parseTagYear(raw string) int {
	raw = strings.TrimSpace(raw)
	if len(raw) >= 4 {
		raw = raw[:4]
	}
	year := 0
	for _, r := range raw {
		if r < '0' || r > '9' {
			return 0
		}
		year = year*10 + int(r-'0')
	}
	if year < 1888 || year > time.Now().Year()+2 {
		return 0
	}
	return year
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
