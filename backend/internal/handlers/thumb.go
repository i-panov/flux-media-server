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

const (
	// maxCoverSize — максимальный размер загружаемой обложки (10 МБ).
	maxCoverSize = 10 << 20
	// coverCacheMaxAge — Cache-Control для обложек/превью (1 день).
	coverCacheMaxAge = 86400
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
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	thumbPath := h.thumbSvc.GetPath(mediaID)
	if !h.thumbSvc.Exists(mediaID) {
		return response.Error(c, fiber.StatusNotFound, "Thumbnail not available")
	}

	// Determine content type from extension.
	ext := filepath.Ext(thumbPath)
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "image/jpeg"
	}

	c.Set("Content-Type", contentType)
	c.Set("Cache-Control", fmt.Sprintf("public, max-age=%d", coverCacheMaxAge))

	return c.SendFile(thumbPath)
}

// GetCover returns the embedded cover art for a media item.
func (h *ThumbHandler) GetCover(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Check if cover URL is set (флаг непустоты).
	if media.CoverURL == "" {
		return response.Error(c, fiber.StatusNotFound, "Cover not available")
	}

	// Файл ищем по известным расширениям, а не по значению CoverURL —
	// в БД теперь хранится относительный URL, а не путь ФС.
	coverPath := h.thumbSvc.FindCoverPath(mediaID)
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
	c.Set("Cache-Control", fmt.Sprintf("public, max-age=%d", coverCacheMaxAge))

	return c.SendFile(coverPath)
}

var allowedCoverExtensions = map[string]bool{
	".jpg":  true,
	".jpeg": true,
	".png":  true,
	".webp": true,
}

// minImageBytes — минимальный читаемый заголовок: покрывает полный magic
// JPEG (FF D8 FF + следующий маркер), PNG (8 байт) и WebP (12 байт RIFF).
const minImageBytes = 12

// detectImageFormat определяет формат изображения по magic bytes.
// Возвращает расширение (".jpg", ".png", ".webp") или пустую строку.
func detectImageFormat(head []byte) string {
	// Слишком короткий файл не может быть валидным изображением: 3 байта
	// "FF D8 FF" — это не JPEG, а лишь фрагмент magic.
	if len(head) < minImageBytes {
		return ""
	}
	if head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF {
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
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Get uploaded file.
	fileHeader, err := c.FormFile("cover")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Cover image file is required")
	}

	// Check file size (max 10 MB) — до чтения содержимого в память.
	if fileHeader.Size > maxCoverSize {
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
	head := make([]byte, minImageBytes)
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

	coverPath := h.thumbSvc.CoverPathForExt(mediaID, actualExt)
	if err := os.MkdirAll(filepath.Dir(coverPath), 0755); err != nil {
		log.Printf("UploadCover: mkdir: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}

	// Сначала сохраняем новую обложку — при сбое записи старая остаётся
	// нетронутой. Файл с тем же расширением перезаписывается, остальные
	// расширения удаляются только после успешного сохранения.
	if err := c.SaveFile(fileHeader, coverPath); err != nil {
		log.Printf("UploadCover: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}
	for _, oldExt := range []string{".jpg", ".png", ".webp"} {
		if oldExt == actualExt {
			continue
		}
		oldPath := h.thumbSvc.CoverPathForExt(mediaID, oldExt)
		if err := os.Remove(oldPath); err != nil && !os.IsNotExist(err) {
			log.Printf("UploadCover: remove old cover %s: %v", oldPath, err)
		}
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
