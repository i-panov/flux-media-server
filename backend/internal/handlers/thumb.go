package handlers

import (
	"mime"
	"path/filepath"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// ThumbHandler serves media thumbnails.
type ThumbHandler struct {
 mediaRepo  repository.MediaRepository
 thumbSvc   *services.ThumbnailService
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
