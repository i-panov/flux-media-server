package services

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type ThumbnailService struct {
	thumbnailPath string
	ffmpegPath    string
}

func NewThumbnailService(thumbnailPath string) *ThumbnailService {
	ffmpegPath, _ := exec.LookPath("ffmpeg")
	return &ThumbnailService{
		thumbnailPath: thumbnailPath,
		ffmpegPath:    ffmpegPath,
	}
}

func (s *ThumbnailService) IsAvailable() bool {
	return s.ffmpegPath != ""
}

func (s *ThumbnailService) Generate(videoPath string) (string, error) {
	if !s.IsAvailable() {
		return "", fmt.Errorf("ffmpeg not available")
	}

	if err := os.MkdirAll(s.thumbnailPath, 0755); err != nil {
		return "", err
	}

	baseName := filepath.Base(videoPath)
	nameWithoutExt := strings.TrimSuffix(baseName, filepath.Ext(baseName))
	thumbPath := filepath.Join(s.thumbnailPath, nameWithoutExt+".jpg")

	if _, err := os.Stat(thumbPath); err == nil {
		return thumbPath, nil
	}

	cmd := exec.Command(s.ffmpegPath,
		"-i", videoPath,
		"-ss", "00:00:10",
		"-vframes", "1",
		"-vf", "scale=320:-1",
		"-y",
		thumbPath,
	)

	if output, err := cmd.CombinedOutput(); err != nil {
		log.Printf("FFmpeg thumbnail error: %s", string(output))
		return "", err
	}

	return thumbPath, nil
}
