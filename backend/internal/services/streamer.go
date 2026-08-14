package services

import (
	"context"
	"errors"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/response"
)

type StreamerService struct {
	mediaPaths []config.MediaPath
}

func NewStreamerService(cfg *config.Config) *StreamerService {
	return &StreamerService{mediaPaths: cfg.Media.MediaPaths()}
}

func (s *StreamerService) IsPathAllowed(ctx context.Context, filePath string) (bool, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return false, err
	}

	// Resolve symlinks to prevent traversal via symlinks
	resolvedPath, err := filepath.EvalSymlinks(absPath)
	if err != nil {
		// File might not exist yet; fall back to abs path
		resolvedPath = absPath
	}

	for _, mp := range s.mediaPaths {
		if mp.Path == "" {
			continue
		}
		absLibPath, err := filepath.Abs(mp.Path)
		if err != nil {
			continue
		}
		// Also resolve symlinks for media path
		resolvedLibPath, err := filepath.EvalSymlinks(absLibPath)
		if err != nil {
			resolvedLibPath = absLibPath
		}
		if strings.HasPrefix(resolvedPath, resolvedLibPath+string(filepath.Separator)) || resolvedPath == resolvedLibPath {
			return true, nil
		}
	}

	return false, nil
}

func (s *StreamerService) Stream(c *fiber.Ctx, filePath string) error {
	ctx := c.UserContext()

	// Resolve the path once and stream the RESOLVED path: this closes the
	// TOCTOU window where the file could be swapped between the permission
	// check and SendFile (e.g. via a symlink).
	allowed, resolvedPath, err := s.resolveAllowedPath(ctx, filePath)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "Access denied")
	}

	ext := strings.ToLower(filepath.Ext(resolvedPath))
	c.Set("Content-Type", mimeTypeByExt(ext))

	// SendFile сам возвращает 404 (fiber.Error) для отсутствующего файла.
	// Отдельный os.Stat не нужен — он давал бы лишний системный вызов,
	// а fasthttp всё равно проверяет файл при отправке.
	if err := c.SendFile(resolvedPath); err != nil {
		var fiberErr *fiber.Error
		if errors.As(err, &fiberErr) && fiberErr.Code == fiber.StatusNotFound {
			// Не возвращаем текст ошибки SendFile — он содержит путь ФС.
			return response.Error(c, fiber.StatusNotFound, "File not found")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to stream file")
	}
	return nil
}

// resolveAllowedPath checks filePath against the registered media paths and
// returns the resolved (symlink-free) path that was actually validated.
func (s *StreamerService) resolveAllowedPath(ctx context.Context, filePath string) (bool, string, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return false, "", err
	}

	// Resolve symlinks to prevent traversal via symlinks.
	resolvedPath, err := filepath.EvalSymlinks(absPath)
	if err != nil {
		// File might not exist yet; fall back to abs path.
		resolvedPath = absPath
	}

	for _, mp := range s.mediaPaths {
		if mp.Path == "" {
			continue
		}
		absLibPath, err := filepath.Abs(mp.Path)
		if err != nil {
			continue
		}
		// Also resolve symlinks for media path.
		resolvedLibPath, err := filepath.EvalSymlinks(absLibPath)
		if err != nil {
			resolvedLibPath = absLibPath
		}
		if strings.HasPrefix(resolvedPath, resolvedLibPath+string(filepath.Separator)) || resolvedPath == resolvedLibPath {
			return true, resolvedPath, nil
		}
	}

	return false, resolvedPath, nil
}

// mimeTypeByExt returns the MIME type for known media file extensions.
func mimeTypeByExt(ext string) string {
	switch ext {
	case ".mp4", ".m4v":
		return "video/mp4"
	case ".mkv":
		return "video/x-matroska"
	case ".avi":
		return "video/x-msvideo"
	case ".mov":
		return "video/quicktime"
	case ".wmv":
		return "video/x-ms-wmv"
	case ".webm":
		return "video/webm"
	case ".flv":
		return "video/x-flv"
	case ".ts":
		return "video/mp2t"
	case ".mp3":
		return "audio/mpeg"
	case ".flac":
		return "audio/flac"
	case ".ogg", ".oga":
		return "audio/ogg"
	case ".m4a":
		return "audio/mp4"
	case ".aac":
		return "audio/aac"
	case ".wav":
		return "audio/wav"
	case ".opus":
		return "audio/opus"
	case ".wma":
		return "audio/x-ms-wma"
	default:
		return "application/octet-stream"
	}
}
