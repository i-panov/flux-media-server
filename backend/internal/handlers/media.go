package handlers

import (
	"errors"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type MediaHandler struct {
	mediaRepo repository.MediaRepository
	streamer  services.StreamerInterface
	thumbSvc  *services.ThumbnailService
}

func NewMediaHandler(mediaRepo repository.MediaRepository, streamer services.StreamerInterface, thumbSvc *services.ThumbnailService) *MediaHandler {
	return &MediaHandler{
		mediaRepo: mediaRepo,
		streamer:  streamer,
		thumbSvc:  thumbSvc,
	}
}

type CreateMediaRequest struct {
	Title       string           `json:"title"`
	Year        int              `json:"year"`
	Description string           `json:"description"`
	Type        models.MediaType `json:"type"`
	FilePath    string           `json:"file_path"`
}

func isValidMediaType(t string) bool {
	return t == "" || models.ParseMediaType(t).Valid()
}

func (h *MediaHandler) List(c *fiber.Ctx) error {
	filters := make(map[string]interface{})

	if mediaType := c.Query("type"); mediaType != "" {
		if !isValidMediaType(mediaType) {
			return response.Error(c, fiber.StatusBadRequest, "invalid type")
		}
		filters["type"] = mediaType
	}
	if year := c.Query("year"); year != "" {
		filters["year"] = year
	}
	if q := c.Query("q"); q != "" {
		filters["q"] = q
	}

	limit := c.QueryInt("limit", 20)
	offset := c.QueryInt("offset", 0)
	// Bound the page size: an unbounded limit allows fetching the whole
	// library in one request (memory/DoS vector on large libraries).
	if limit <= 0 {
		limit = 20
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	ctx := c.UserContext()
	media, total, err := h.mediaRepo.FindAll(ctx, filters, limit, offset)
	if err != nil {
		log.Printf("FindAll: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch media")
	}

	return c.JSON(fiber.Map{
		"items":  media,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *MediaHandler) Get(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	return c.JSON(media)
}

func (h *MediaHandler) Create(c *fiber.Ctx) error {
	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Title == "" {
		return response.Error(c, fiber.StatusBadRequest, "Title is required")
	}
	if req.FilePath == "" {
		return response.Error(c, fiber.StatusBadRequest, "FilePath is required")
	}
	if req.Type == "" || !models.ParseMediaType(string(req.Type)).Valid() {
		return response.Error(c, fiber.StatusBadRequest, "Invalid type")
	}

	ctx := c.UserContext()
	allowed, err := h.streamer.IsPathAllowed(ctx, req.FilePath)
	if err != nil {
		log.Printf("IsPathAllowed: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "File path is not within any registered library")
	}

	media := &models.Media{
		Title:       req.Title,
		Year:        req.Year,
		Description: req.Description,
		Type:        req.Type,
		FilePath:    req.FilePath,
	}

	if err := h.mediaRepo.Create(ctx, media); err != nil {
		log.Printf("Create: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create media")
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

func (h *MediaHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Title == "" {
		return response.Error(c, fiber.StatusBadRequest, "Title is required")
	}
	if req.FilePath == "" {
		return response.Error(c, fiber.StatusBadRequest, "FilePath is required")
	}
	if req.Type != "" && !models.ParseMediaType(string(req.Type)).Valid() {
		return response.Error(c, fiber.StatusBadRequest, "Invalid type")
	}

	allowed, err := h.streamer.IsPathAllowed(ctx, req.FilePath)
	if err != nil {
		log.Printf("IsPathAllowed: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "File path is not within any registered library")
	}

	media.Title = req.Title
	media.Year = req.Year
	media.Description = req.Description
	media.Type = req.Type
	media.FilePath = req.FilePath

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update media")
	}

	return c.JSON(media)
}

func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Get media record to find file path.
	media, err := h.mediaRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	// Delete the database record FIRST. If this fails the files remain on
	// disk (safe — they can be cleaned up later). If we deleted files first
	// and the DB delete failed, we'd be left with a "broken" record pointing
	// to non-existent files.
	if err := h.mediaRepo.Delete(ctx, uint(id)); err != nil {
		log.Printf("Delete: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete media")
	}

	// Now safe to delete files from disk — the record is gone.
	if media.FilePath != "" {
		if err := os.Remove(media.FilePath); err != nil && !os.IsNotExist(err) {
			log.Printf("Delete: remove file %s: %v", media.FilePath, err)
		}
	}

	// Delete thumbnail — файл ищется по ID, а не по ThumbnailURL
	// (в БД теперь относительный URL, а не путь ФС).
	if h.thumbSvc != nil {
		thumbPath := h.thumbSvc.GetPath(media.ID)
		if err := os.Remove(thumbPath); err != nil && !os.IsNotExist(err) {
			log.Printf("Delete: remove thumbnail %s: %v", thumbPath, err)
		}

		// Delete cover (все известные форматы).
		h.thumbSvc.RemoveCovers(media.ID)
	}

	return c.JSON(fiber.Map{"message": "Media deleted successfully"})
}

func (h *MediaHandler) CheckHash(c *fiber.Ctx) error {
	var req struct {
		Hash string `json:"hash"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Hash == "" {
		return response.Error(c, fiber.StatusBadRequest, "Hash is required")
	}

	ctx := c.UserContext()
	existing, err := h.mediaRepo.FindByHash(ctx, req.Hash)
	if err != nil {
		// Ошибка БД — это не "hash не найден": логируем и возвращаем 500,
		// чтобы клиент не принял сбой за отсутствие дубликата.
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("CheckHash: FindByHash: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to check hash")
		}
	}
	if existing != nil {
		return c.JSON(fiber.Map{
			"exists": true,
			"media": fiber.Map{
				"id":    existing.ID,
				"title": existing.Title,
			},
		})
	}

	return c.JSON(fiber.Map{"exists": false})
}

func (h *MediaHandler) Stream(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	return h.streamer.Stream(c, media.FilePath)
}
