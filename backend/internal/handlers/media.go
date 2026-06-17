package handlers

import (
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

type MediaHandler struct {
	mediaRepo *repository.MediaRepository
	streamer  *services.StreamerService
}

func NewMediaHandler(mediaRepo *repository.MediaRepository, streamer *services.StreamerService) *MediaHandler {
	return &MediaHandler{
		mediaRepo: mediaRepo,
		streamer:  streamer,
	}
}

type CreateMediaRequest struct {
	Title       string `json:"title"`
	Year        int    `json:"year"`
	Description string `json:"description"`
	Type        string `json:"type"`
	FilePath    string `json:"file_path"`
}

func (h *MediaHandler) List(c *fiber.Ctx) error {
	filters := make(map[string]interface{})

	if mediaType := c.Query("type"); mediaType != "" {
		filters["type"] = mediaType
	}
	if year := c.Query("year"); year != "" {
		filters["year"] = year
	}

	limit := c.QueryInt("limit", 20)
	offset := c.QueryInt("offset", 0)

	media, total, err := h.mediaRepo.FindAll(filters, limit, offset)
	if err != nil {
		log.Printf("FindAll: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch media",
		})
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
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	return c.JSON(media)
}

func (h *MediaHandler) Create(c *fiber.Ctx) error {
	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.Title == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Title is required",
		})
	}
	if req.FilePath == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "FilePath is required",
		})
	}

	media := &models.Media{
		Title:       req.Title,
		Year:        req.Year,
		Description: req.Description,
		Type:        req.Type,
		FilePath:    req.FilePath,
	}

	if err := h.mediaRepo.Create(media); err != nil {
		log.Printf("Create: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create media",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

func (h *MediaHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.Title == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Title is required",
		})
	}
	if req.FilePath == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "FilePath is required",
		})
	}

	media.Title = req.Title
	media.Year = req.Year
	media.Description = req.Description
	media.Type = req.Type
	media.FilePath = req.FilePath

	if err := h.mediaRepo.Update(media); err != nil {
		log.Printf("Update: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update media",
		})
	}

	return c.JSON(media)
}

func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	if err := h.mediaRepo.Delete(uint(id)); err != nil {
		log.Printf("Delete: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete media",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Media deleted successfully",
	})
}

func (h *MediaHandler) Stream(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	return h.streamer.Stream(c, media.FilePath)
}
