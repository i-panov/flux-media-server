package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
)

type StreamerService struct {
	libraryRepo repository.LibraryRepository
}

func NewStreamerService(libraryRepo repository.LibraryRepository) *StreamerService {
	return &StreamerService{libraryRepo: libraryRepo}
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

	libraries, err := s.libraryRepo.FindAll(ctx)
	if err != nil {
		return false, err
	}

	for _, lib := range libraries {
		// Disabled libraries must not serve files.
		if !lib.Enabled {
			continue
		}
		absLibPath, err := filepath.Abs(lib.Path)
		if err != nil {
			continue
		}
		// Also resolve symlinks for library path
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

	allowed, err := s.IsPathAllowed(ctx, filePath)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "Access denied")
	}

	ext := strings.ToLower(filepath.Ext(filePath))
	c.Set("Content-Type", mimeTypeByExt(ext))

	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		return response.Error(c, fiber.StatusNotFound, err.Error())
	}

	return c.SendFile(filePath)
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

// parseRangeHeader parses a Range header value like "bytes=0-499" and returns
// validated start and end byte positions.
func parseRangeHeader(rangeHeader string, fileSize int64) (start, end int64, err error) {
	if !strings.HasPrefix(rangeHeader, "bytes=") {
		return 0, 0, fmt.Errorf("invalid range unit")
	}

	ranges := strings.TrimPrefix(rangeHeader, "bytes=")
	parts := strings.SplitN(ranges, "-", 2)
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid range format")
	}

	if parts[0] == "" {
		// Suffix range: "-500" means last 500 bytes
		suffixLen, parseErr := strconv.ParseInt(parts[1], 10, 64)
		if parseErr != nil || suffixLen <= 0 {
			return 0, 0, fmt.Errorf("invalid suffix range")
		}
		if suffixLen > fileSize {
			suffixLen = fileSize
		}
		return fileSize - suffixLen, fileSize - 1, nil
	}

	start, err = strconv.ParseInt(parts[0], 10, 64)
	if err != nil || start < 0 || start >= fileSize {
		return 0, 0, fmt.Errorf("invalid range start")
	}

	if parts[1] == "" {
		end = fileSize - 1
	} else {
		end, err = strconv.ParseInt(parts[1], 10, 64)
		if err != nil || end < start || end >= fileSize {
			return 0, 0, fmt.Errorf("invalid range end")
		}
	}

	return start, end, nil
}
