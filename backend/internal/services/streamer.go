package services

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
)

type StreamerService struct{}

func NewStreamerService() *StreamerService {
	return &StreamerService{}
}

func (s *StreamerService) Stream(c *fiber.Ctx, filePath string) error {
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
