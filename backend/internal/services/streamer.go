package services

import (
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
	libraryRepo *repository.LibraryRepository
}

func NewStreamerService(libraryRepo *repository.LibraryRepository) *StreamerService {
	return &StreamerService{libraryRepo: libraryRepo}
}

func (s *StreamerService) isPathAllowed(filePath string) (bool, error) {
	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return false, err
	}

	libraries, err := s.libraryRepo.FindAll()
	if err != nil {
		return false, err
	}

	for _, lib := range libraries {
		absLibPath, err := filepath.Abs(lib.Path)
		if err != nil {
			continue
		}
		if strings.HasPrefix(absPath, absLibPath+string(filepath.Separator)) || absPath == absLibPath {
			return true, nil
		}
	}

	return false, nil
}

func (s *StreamerService) Stream(c *fiber.Ctx, filePath string) error {
	allowed, err := s.isPathAllowed(filePath)
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
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to open file",
		})
	}
	defer file.Close()

	// Get file size
	stat, err := file.Stat()
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to get file info",
		})
	}

	fileSize := stat.Size()

	// Set content type based on extension
	ext := strings.ToLower(filePath[strings.LastIndex(filePath, "."):])
	contentType := "application/octet-stream"
	switch ext {
	case ".mp4":
		contentType = "video/mp4"
	case ".mkv":
		contentType = "video/x-matroska"
	case ".avi":
		contentType = "video/x-msvideo"
	case ".mov":
		contentType = "video/quicktime"
	}

	// Handle Range request
	rangeHeader := c.Get("Range")
	if rangeHeader != "" {
		ranges := strings.Replace(rangeHeader, "bytes=", "", 1)
		parts := strings.Split(ranges, "-")

		start, _ := strconv.ParseInt(parts[0], 10, 64)
		end := fileSize - 1
		if len(parts) > 1 && parts[1] != "" {
			end, _ = strconv.ParseInt(parts[1], 10, 64)
		}

		if start < 0 || start >= fileSize || end < start || end >= fileSize {
			return c.Status(fiber.StatusRequestedRangeNotSatisfiable).JSON(fiber.Map{
				"error": "Range not satisfiable",
			})
		}

		contentLength := end - start + 1

		c.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, fileSize))
		c.Set("Content-Length", strconv.FormatInt(contentLength, 10))
		c.Set("Accept-Ranges", "bytes")
		c.Status(fiber.StatusPartialContent)

		file.Seek(start, io.SeekStart)
		io.CopyN(c.Response().BodyWriter(), file, contentLength)
	} else {
		c.Set("Content-Length", strconv.FormatInt(fileSize, 10))
		c.Set("Accept-Ranges", "bytes")
		io.Copy(c.Response().BodyWriter(), file)
	}

	c.Set("Content-Type", contentType)
	return nil
}
