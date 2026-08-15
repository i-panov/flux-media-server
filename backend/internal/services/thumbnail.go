package services

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/vansante/go-ffprobe.v2"
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
	return s.GenerateWithContext(context.Background(), mediaID, filePath)
}

// GenerateWithContext — то же, что Generate, но с учётом отмены контекста
// (используется сканером; ffmpeg убивается через CommandContext).
func (s *ThumbnailService) GenerateWithContext(ctx context.Context, mediaID uint, filePath string) string {
	ext := strings.ToLower(filepath.Ext(filePath))
	if videoExtensions[ext] {
		return s.generateVideoThumbnail(ctx, mediaID, filePath)
	}
	return ""
}

// ExtractCover extracts embedded album art from audio or video files.
// Returns the path to the extracted cover, or empty string on failure.
func (s *ThumbnailService) ExtractCover(mediaID uint, filePath string) string {
	return s.ExtractCoverContext(context.Background(), mediaID, filePath)
}

// ExtractCoverContext — то же, что ExtractCover, но с учётом отмены контекста.
func (s *ThumbnailService) ExtractCoverContext(ctx context.Context, mediaID uint, filePath string) string {
	return s.extractEmbeddedArt(ctx, mediaID, filePath)
}

// GetCoverPath returns the cover path for a media ID.
func (s *ThumbnailService) GetCoverPath(mediaID uint) string {
	return filepath.Join(s.thumbnailsDir, fmt.Sprintf("%d_cover.jpg", mediaID))
}

// CoverPathForExt возвращает путь к обложке с заданным расширением.
// Используется UploadCover для сохранения файла с фактическим форматом.
func (s *ThumbnailService) CoverPathForExt(mediaID uint, ext string) string {
	return filepath.Join(s.thumbnailsDir, fmt.Sprintf("%d_cover%s", mediaID, ext))
}

// FindCoverPath возвращает путь к существующей обложке (jpg/png/webp/gif)
// или пустую строку, если обложки нет.
func (s *ThumbnailService) FindCoverPath(mediaID uint) string {
	for _, ext := range []string{".jpg", ".png", ".webp", ".gif"} {
		p := s.CoverPathForExt(mediaID, ext)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

// RemoveCovers удаляет все файлы обложек для mediaID (все известные форматы).
func (s *ThumbnailService) RemoveCovers(mediaID uint) {
	for _, ext := range []string{".jpg", ".png", ".webp", ".gif"} {
		p := s.CoverPathForExt(mediaID, ext)
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			log.Printf("thumb: remove cover %s: %v", p, err)
		}
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
// Кадр берётся на отметке min(10 секунд, 10% длительности): для коротких
// роликов фиксированная -ss 10 уезжала бы в конец или за границы.
func (s *ThumbnailService) generateVideoThumbnail(ctx context.Context, mediaID uint, filePath string) string {
	outPath := s.GetPath(mediaID)

	// Ensure thumbnails directory exists.
	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		log.Printf("thumb: mkdir %s: %v", s.thumbnailsDir, err)
		return ""
	}

	ss := "10"
	if dur := probeDuration(ctx, filePath); dur > 0 {
		if tenth := dur * 0.1; tenth < 10 {
			ss = fmt.Sprintf("%.2f", tenth)
		}
	}

	// Use a timeout so one broken/corrupt file cannot hang the whole scan.
	cmdCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cmdCtx, "ffmpeg",
		"-ss", ss,
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

// probeDuration возвращает длительность видео в секундах (0 при ошибке).
func probeDuration(ctx context.Context, filePath string) float64 {
	probeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	data, err := ffprobe.ProbeURL(probeCtx, filePath)
	if err != nil {
		log.Printf("thumb: ffprobe duration for %s: %v", filePath, err)
		return 0
	}
	return data.Format.Duration().Seconds()
}

// extractEmbeddedArt extracts embedded album art using ffmpeg.
func (s *ThumbnailService) extractEmbeddedArt(ctx context.Context, mediaID uint, filePath string) string {
	// Формат обложки заранее неизвестен (jpg/png/webp/gif), поэтому
	// извлекаем во временный .jpg и переименовываем по фактическому
	// формату — FindCoverPath поддерживает все варианты.
	outPath := s.GetCoverPath(mediaID)

	// Ensure thumbnails directory exists.
	if err := os.MkdirAll(s.thumbnailsDir, 0755); err != nil {
		log.Printf("thumb: mkdir %s: %v", s.thumbnailsDir, err)
		return ""
	}

	// Use a timeout so a hung ffmpeg cannot block the worker indefinitely.
	cmdCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cmdCtx, "ffmpeg",
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

	final := s.CoverPathForExt(mediaID, detectImageFormat(outPath))
	if final != outPath {
		_ = os.Remove(final) // старая копия с другим расширением
		if err := os.Rename(outPath, final); err != nil {
			log.Printf("thumb: rename cover %s -> %s: %v", outPath, final, err)
			return outPath
		}
		return final
	}
	return outPath
}

// detectImageFormat определяет формат изображения по сигнатуре файла.
func detectImageFormat(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ".jpg"
	}
	defer f.Close()

	head := make([]byte, 12)
	n, _ := f.Read(head)
	head = head[:n]

	switch {
	case len(head) >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF:
		return ".jpg"
	case len(head) >= 8 && string(head[0:8]) == "\x89PNG\r\n\x1a\n":
		return ".png"
	case len(head) >= 12 && string(head[0:4]) == "RIFF" && string(head[8:12]) == "WEBP":
		return ".webp"
	case len(head) >= 6 && string(head[0:3]) == "GIF" && (head[3] == '8'):
		return ".gif"
	default:
		return ".jpg"
	}
}
