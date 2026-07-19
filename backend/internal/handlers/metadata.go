package handlers

import (
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type MetadataHandler struct {
	mediaRepo repository.MediaRepository
}

func NewMetadataHandler(mediaRepo repository.MediaRepository) *MetadataHandler {
	return &MetadataHandler{mediaRepo: mediaRepo}
}

type SearchResponse struct {
	Title string `json:"title"`
	Year  int    `json:"year"`
}

func (h *MetadataHandler) Search(c *fiber.Ctx) error {
	query := c.Query("q")
	if query == "" {
		return response.Error(c, fiber.StatusBadRequest, "Query parameter 'q' is required")
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
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	title, year := metadata.ParseFilename(media.FilePath)

	media.Title = title
	media.Year = year

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update metadata")
	}

	return c.JSON(media)
}

func (h *MetadataHandler) Update(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, uint(mediaID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	var req struct {
		Title       string  `json:"title"`
		Description string  `json:"description"`
		PosterURL   string  `json:"poster_url"`
		Rating      float64 `json:"rating"`
		Genres      string  `json:"genres"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
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

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update metadata")
	}

	return c.JSON(media.Metadata)
}
