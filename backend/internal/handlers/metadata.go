package handlers

import (
	"log"
	"path/filepath"

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

	// Parse only the filename, not the full path (otherwise directories
	// end up in the title).
	title, year := metadata.ParseFilename(filepath.Base(media.FilePath))

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

	// Pointer fields allow distinguishing "not provided" from "set to empty",
	// so values can also be cleared.
	var req struct {
		Title       *string  `json:"title"`
		Description *string  `json:"description"`
		PosterURL   *string  `json:"poster_url"`
		Rating      *float64 `json:"rating"`
		Genres      *string  `json:"genres"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if media.Metadata == nil {
		media.Metadata = &models.Metadata{}
	}

	if req.Title != nil {
		media.Metadata.Title = *req.Title
	}
	if req.Description != nil {
		media.Metadata.Description = *req.Description
	}
	if req.PosterURL != nil {
		media.Metadata.PosterURL = *req.PosterURL
	}
	if req.Rating != nil {
		media.Metadata.Rating = *req.Rating
	}
	if req.Genres != nil {
		media.Metadata.Genres = *req.Genres
	}

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update metadata")
	}

	return c.JSON(media.Metadata)
}
