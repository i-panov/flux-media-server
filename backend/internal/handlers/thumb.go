package handlers

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"mime"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// ThumbHandler serves media thumbnails.
type ThumbHandler struct {
	mediaRepo repository.MediaRepository
	thumbSvc  *services.ThumbnailService
}

// NewThumbHandler creates a new ThumbHandler.
func NewThumbHandler(mediaRepo repository.MediaRepository, thumbSvc *services.ThumbnailService) *ThumbHandler {
	return &ThumbHandler{mediaRepo: mediaRepo, thumbSvc: thumbSvc}
}

// Get returns the thumbnail for a media item.
func (h *ThumbHandler) Get(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	_, err = h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	thumbPath := h.thumbSvc.GetPath(uint(mediaID))
	if !h.thumbSvc.Exists(uint(mediaID)) {
		return response.Error(c, fiber.StatusNotFound, "Thumbnail not available")
	}

	// Determine content type from extension.
	ext := filepath.Ext(thumbPath)
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "image/jpeg"
	}

	c.Set("Content-Type", contentType)
	c.Set("Cache-Control", "public, max-age=86400")

	return c.SendFile(thumbPath)
}

// GetCover returns the embedded cover art for a media item.
func (h *ThumbHandler) GetCover(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	// Check if cover URL is set (флаг непустоты).
	if media.CoverURL == "" {
		return response.Error(c, fiber.StatusNotFound, "Cover not available")
	}

	// Файл ищем по известным расширениям, а не по значению CoverURL —
	// в БД теперь хранится относительный URL, а не путь ФС.
	coverPath := h.thumbSvc.FindCoverPath(uint(mediaID))
	if coverPath == "" {
		return response.Error(c, fiber.StatusNotFound, "Cover not available")
	}

	// Determine content type from extension.
	ext := filepath.Ext(coverPath)
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "image/jpeg"
	}

	c.Set("Content-Type", contentType)
	c.Set("Cache-Control", "public, max-age=86400")

	return c.SendFile(coverPath)
}

var allowedCoverExtensions = map[string]bool{
	".jpg":  true,
	".jpeg": true,
	".png":  true,
	".webp": true,
}

// detectImageFormat определяет формат изображения по magic bytes.
// Возвращает расширение (".jpg", ".png", ".webp") или пустую строку.
func detectImageFormat(head []byte) string {
	if len(head) >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF {
		return ".jpg"
	}
	if len(head) >= 8 && bytes.Equal(head[:8], []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}) {
		return ".png"
	}
	if len(head) >= 12 && string(head[:4]) == "RIFF" && string(head[8:12]) == "WEBP" {
		return ".webp"
	}
	return ""
}

// UploadCover accepts a cover image upload and replaces the existing cover
// for a media item. Accepts JPEG, PNG, and WebP images up to 10 MB.
func (h *ThumbHandler) UploadCover(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	// Get uploaded file.
	fileHeader, err := c.FormFile("cover")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Cover image file is required")
	}

	// Check file size (max 10 MB).
	if fileHeader.Size > 10<<20 {
		return response.Error(c, fiber.StatusRequestEntityTooLarge, "Cover image too large (max 10 MB)")
	}

	// Validate extension.
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !allowedCoverExtensions[ext] {
		return response.Error(c, fiber.StatusBadRequest, "Invalid cover format. Allowed: jpg, jpeg, png, webp")
	}

	// Валидируем содержимое по magic bytes — расширение файла может лгать.
	uploaded, err := fileHeader.Open()
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Failed to read cover file")
	}
	head := make([]byte, 12)
	n, readErr := io.ReadFull(uploaded, head)
	uploaded.Close()
	if readErr != nil && readErr != io.EOF && readErr != io.ErrUnexpectedEOF {
		return response.Error(c, fiber.StatusBadRequest, "Failed to read cover file")
	}

	// Сохраняем с расширением, соответствующим фактическому формату.
	actualExt := detectImageFormat(head[:n])
	if actualExt == "" {
		return response.Error(c, fiber.StatusBadRequest, "Invalid image content. Allowed: JPEG, PNG, WebP")
	}

	coverPath := h.thumbSvc.CoverPathForExt(uint(mediaID), actualExt)
	if err := os.MkdirAll(filepath.Dir(coverPath), 0755); err != nil {
		log.Printf("UploadCover: mkdir: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}

	// Удаляем старые обложки с другими расширениями ДО сохранения новой,
	// чтобы не затереть только что записанный файл.
	h.thumbSvc.RemoveCovers(uint(mediaID))

	if err := c.SaveFile(fileHeader, coverPath); err != nil {
		log.Printf("UploadCover: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}

	// В БД сохраняем относительный URL, а не путь ФС.
	coverURL := fmt.Sprintf("/api/media/%d/cover", mediaID)
	media.CoverURL = coverURL
	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("UploadCover: update media: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update cover")
	}

	return c.JSON(fiber.Map{"cover_url": coverURL})
}
