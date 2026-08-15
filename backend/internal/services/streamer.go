package services

import (
	"context"
	"path/filepath"
	"strings"

	"flux/internal/config"
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

// ResolveStreamPath проверяет filePath на принадлежность зарегистрированным
// медиа-путям и возвращает резолвнутый (без символьных ссылок) путь, который
// фактически был проверен. HTTP-слой отсутствует: вызовов c.ServeFile/SendFile
// здесь нет — этим занимается хендлер, который и маппит ошибки на статусы.
// Возвращает resolvedPath даже при allowed=false: он нужен только когда
// allowed=true (безопасность: разрешено отдавать исключительно проверенный
// путь, иначе клиент мог бы подменить файл в TOCTOU-окне).
func (s *StreamerService) ResolveStreamPath(ctx context.Context, filePath string) (bool, string, error) {
	return s.resolveAllowedPath(ctx, filePath)
}
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

// MimeTypeByExt returns the MIME type for known media file extensions.
func MimeTypeByExt(ext string) string {
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
