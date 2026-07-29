package services

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
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
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to validate file path",
		})
	}
	if !allowed {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "Access denied",
		})
	}

	file, err := os.Open(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "File not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to open file",
		})
	}
	defer file.Close()

	stat, err := file.Stat()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to get file info",
		})
	}

	fileSize := stat.Size()

	// Set content type based on extension
	ext := strings.ToLower(filepath.Ext(filePath))
	contentType := mimeTypeByExt(ext)

	c.Set("Accept-Ranges", "bytes")

	// Handle Range request
	rangeHeader := c.Get("Range")
	if rangeHeader != "" {
		start, end, err := parseRangeHeader(rangeHeader, fileSize)
		if err != nil {
			// Note: Content-Type is set only after the range is validated,
			// so the 416 error carries a JSON content type.
			return c.Status(fiber.StatusRequestedRangeNotSatisfiable).JSON(fiber.Map{
				"error": "Range not satisfiable",
			})
		}

		c.Set("Content-Type", contentType)

		contentLength := end - start + 1

		c.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, fileSize))
		c.Set("Content-Length", strconv.FormatInt(contentLength, 10))
		c.Status(fiber.StatusPartialContent)

		file.Seek(start, io.SeekStart)
		if _, err := io.CopyN(c.Response().BodyWriter(), file, contentLength); err != nil {
			// Client disconnected or write error — not a server error
			return nil
		}
	} else {
		c.Set("Content-Type", contentType)
		c.Set("Content-Length", strconv.FormatInt(fileSize, 10))
		if _, err := io.Copy(c.Response().BodyWriter(), file); err != nil {
			return nil
		}
	}

	return nil
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
