package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

type MetadataHandler struct {
	mediaRepo *repository.MediaRepository
}

func NewMetadataHandler(mediaRepo *repository.MediaRepository) *MetadataHandler {
	return &MetadataHandler{mediaRepo: mediaRepo}
}

type SearchRequest struct {
	Query string `json:"query"`
}

type SearchResponse struct {
	Title string `json:"title"`
	Year  int    `json:"year"`
}

func (h *MetadataHandler) Search(c *fiber.Ctx) error {
	query := c.Query("q")
	if query == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Query parameter 'q' is required",
		})
	}

	title, year := metadata.ParseFilename(query)

	return c.JSON(fiber.Map{
		"results": []SearchResponse{
			{Title: title, Year: year},
		},
	})
}

func (h *MetadataHandler) Refresh(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(mediaID))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	title, year := metadata.ParseFilename(media.FilePath)

	media.Title = title
	media.Year = year

	if err := h.mediaRepo.Update(media); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update metadata",
		})
	}

	return c.JSON(media)
}

func (h *MetadataHandler) Update(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	media, err := h.mediaRepo.FindByID(uint(mediaID))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Media not found",
		})
	}

	var req models.Metadata
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if media.Metadata == nil {
		media.Metadata = &models.Metadata{}
	}

	if req.Title != "" {
		media.Metadata.Title = req.Title
	}
	if req.Description != "" {
		media.Metadata.Description = req.Description
	}
	if req.PosterURL != "" {
		media.Metadata.PosterURL = req.PosterURL
	}
	if req.Rating != 0 {
		media.Metadata.Rating = req.Rating
	}
	if req.Genres != "" {
		media.Metadata.Genres = req.Genres
	}

	if err := h.mediaRepo.Update(media); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update metadata",
		})
	}

	return c.JSON(media.Metadata)
}
