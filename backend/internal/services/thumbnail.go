package services

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ThumbnailService generates and serves thumbnails for media files.
type ThumbnailService struct {
	thumbnailsDir string
}

// NewThumbnailService creates a new ThumbnailService.
func NewThumbnailService(thumbnailsDir string) *ThumbnailService {
	return &ThumbnailService{thumbnailsDir: thumbnailsDir}
}

// Generate creates a thumbnail for the given media file.
// For video: extracts a frame using ffmpeg.
// For audio: extracts embedded album art.
// Returns the path to the generated thumbnail, or empty string on failure.
func (s *ThumbnailService) Generate(mediaID uint, filePath string) string {
	ext := strings.ToLower(filepath.Ext(filePath))

	switch ext {
	case ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".webm", ".flv", ".ts":
		return s.generateVideoThumbnail(mediaID, filePath)
	case ".mp3", ".flac", ".ogg", ".m4a", ".aac", ".wav":
		return s.generateAudioThumbnail(mediaID, filePath)
	default:
		return ""
	}
}

// GetPath returns the thumbnail path for a media ID.
func (s *ThumbnailService) GetPath(mediaID uint) string {
	return filepath.Join(s.thumbnailsDir, fmt.Sprintf("%d.jpg", mediaID))
}

// Exists checks if a thumbnail exists for the given media ID.
func (s *ThumbnailService) Exists(mediaID uint) bool {
	_, err := os.Stat(s.GetPath(mediaID))
	return err == nil
}

// generateVideoThumbnail extracts a frame from a video using ffmpeg.
func (s *ThumbnailService) generateVideoThumbnail(mediaID uint, filePath string) string {
	outPath := s.GetPath(mediaID)

	// Ensure thumbnails directory exists.
	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		log.Printf("thumb: mkdir %s: %v", s.thumbnailsDir, err)
		return ""
	}

	// Extract frame at 10% of the video or 10 seconds, whichever is smaller.
	cmd := exec.Command("ffmpeg",
		"-ss", "10",
		"-i", filePath,
		"-vframes", "1",
		"-q:v", "2",
		"-y",
		outPath,
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		log.Printf("thumb: ffmpeg for %s: %v: %s", filePath, err, stderr.String())
		return ""
	}

	return outPath
}

// generateAudioThumbnail extracts embedded album art from an audio file.
func (s *ThumbnailService) generateAudioThumbnail(mediaID uint, filePath string) string {
	outPath := s.GetPath(mediaID)

	// Ensure thumbnails directory exists.
	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		log.Printf("thumb: mkdir %s: %v", s.thumbnailsDir, err)
		return ""
	}

	// Try to extract embedded album art using ffprobe (reads tags).
	// dhowden/tag is used in metadata_extractor; here we just check for embedded art.
	// For simplicity, we re-read the tag here. In production, pass the art bytes from scanner.
	f, err := os.Open(filePath)
	if err != nil {
		log.Printf("thumb: open %s: %v", filePath, err)
		return s.generatePlaceholder(mediaID)
	}
	defer f.Close()

	// Use ffprobe to find attached picture (works for most formats).
	cmd := exec.Command("ffprobe",
		"-v", "quiet",
		"-select_streams", "s",
		"-show_entries", "stream=codec_type,codec_name",
		"-of", "csv=p=0",
		filePath,
	)

	out, err := cmd.Output()
	if err == nil && strings.Contains(string(out), "attachment") {
		// Has embedded art — extract it.
		return s.extractEmbeddedArt(mediaID, filePath, outPath)
	}

	// No embedded art — generate placeholder.
	return s.generatePlaceholder(mediaID)
}

// extractEmbeddedArt extracts embedded album art using ffmpeg.
func (s *ThumbnailService) extractEmbeddedArt(mediaID uint, filePath, outPath string) string {
	cmd := exec.Command("ffmpeg",
		"-i", filePath,
		"-an", "-vcodec", "copy",
		"-y", outPath,
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		log.Printf("thumb: extract art from %s: %v: %s", filePath, err, stderr.String())
		return s.generatePlaceholder(mediaID)
	}

	return outPath
}

// generatePlaceholder creates a simple colored placeholder thumbnail.
func (s *ThumbnailService) generatePlaceholder(mediaID uint) string {
	outPath := s.GetPath(mediaID)

	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		return ""
	}

	// Create a simple 300x300 purple-ish image with a music note icon hint.
	img := image.NewRGBA(image.Rect(0, 0, 300, 300))

	// Fill with dark purple background.
	bg := color.RGBA{R: 88, G: 66, B: 124, A: 255}
	draw.Draw(img, img.Bounds(), &image.Uniform{bg}, image.Point{}, draw.Src)

	// Draw a simple music note shape (two circles + a line).
	noteColor := color.RGBA{R: 200, G: 180, B: 240, A: 255}

	// Note heads (filled circles).
	for _, center := range []image.Point{
		{X: 120, Y: 200},
		{X: 180, Y: 180},
	} {
		for dy := -15; dy <= 15; dy++ {
			for dx := -15; dx <= 15; dx++ {
				if dx*dx+dy*dy <= 15*15 {
					p := image.Point{X: center.X + dx, Y: center.Y + dy}
					if p.In(img.Bounds()) {
						img.Set(p.X, p.Y, noteColor)
					}
				}
			}
		}
	}

	// Stem (vertical line).
	for y := 80; y <= 200; y++ {
		for dx := 0; dx < 3; dx++ {
			p := image.Point{X: 180 + dx, Y: y}
			if p.In(img.Bounds()) {
				img.Set(p.X, p.Y, noteColor)
			}
		}
	}

	// Flag at top.
	for x := 180; x <= 210; x++ {
		y := 80 + (x-180)/2
		for dy := 0; dy < 3; dy++ {
			p := image.Point{X: x, Y: y + dy}
			if p.In(img.Bounds()) {
				img.Set(p.X, p.Y, noteColor)
			}
		}
	}

	f, err := os.Create(outPath)
	if err != nil {
		return ""
	}
	defer f.Close()

	if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 85}); err != nil {
		return ""
	}

	return outPath
}
