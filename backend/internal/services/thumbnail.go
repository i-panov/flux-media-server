package services

import (
	"bytes"
	"fmt"
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
// For audio: does nothing — the frontend shows a programmatic placeholder.
// Returns the path to the generated thumbnail, or empty string on failure.
func (s *ThumbnailService) Generate(mediaID uint, filePath string) string {
	ext := strings.ToLower(filepath.Ext(filePath))

	switch ext {
	case ".mp4", ".mkv", ".avi", ".mov", ".wmv", ".webm", ".flv", ".ts":
		return s.generateVideoThumbnail(mediaID, filePath)
	default:
		return ""
	}
}

// ExtractCover extracts embedded album art from audio or video files.
// Returns the path to the extracted cover, or empty string on failure.
func (s *ThumbnailService) ExtractCover(mediaID uint, filePath string) string {
	return s.extractEmbeddedArt(mediaID, filePath)
}

// GetCoverPath returns the cover path for a media ID.
func (s *ThumbnailService) GetCoverPath(mediaID uint) string {
	return filepath.Join(s.thumbnailsDir, fmt.Sprintf("%d_cover.jpg", mediaID))
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

// extractEmbeddedArt extracts embedded album art using ffmpeg.
func (s *ThumbnailService) extractEmbeddedArt(mediaID uint, filePath string) string {
	outPath := s.GetCoverPath(mediaID)

	// Ensure thumbnails directory exists.
	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		log.Printf("thumb: mkdir %s: %v", s.thumbnailsDir, err)
		return ""
	}

	cmd := exec.Command("ffmpeg",
		"-i", filePath,
		"-an", "-vcodec", "copy",
		"-y", outPath,
	)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		log.Printf("thumb: extract art from %s: %v: %s", filePath, err, stderr.String())
		return ""
	}

	return outPath
}
