package handlers

import (
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

	// Check if cover URL is set.
	if media.CoverURL == "" {
		return response.Error(c, fiber.StatusNotFound, "Cover not available")
	}

	// Determine content type from extension.
	ext := filepath.Ext(media.CoverURL)
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "image/jpeg"
	}

	c.Set("Content-Type", contentType)
	c.Set("Cache-Control", "public, max-age=86400")

	return c.SendFile(media.CoverURL)
}

var allowedCoverExtensions = map[string]bool{
	".jpg":  true,
	".jpeg": true,
	".png":  true,
	".webp": true,
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

	// Save to thumbnails directory as {id}_cover.jpg.
	coverPath := h.thumbSvc.GetCoverPath(uint(mediaID))
	if err := os.MkdirAll(filepath.Dir(coverPath), 0755); err != nil {
		log.Printf("UploadCover: mkdir: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}

	if err := c.SaveFile(fileHeader, coverPath); err != nil {
		log.Printf("UploadCover: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}

	// Update CoverURL in DB.
	media.CoverURL = coverPath
	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("UploadCover: update media: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update cover")
	}

	return c.JSON(fiber.Map{"cover_url": coverPath})
}
