package handlers

import (
	"log"
	"path/filepath"
	"strings"

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
		Artists     *[]string `json:"artists"`
		Album       *string  `json:"album"`
		Genre       *string  `json:"genre"`
		Year        *int     `json:"year"`
		PosterURL   *string  `json:"poster_url"`
		Rating      *float64 `json:"rating"`
		Genres      *string  `json:"genres"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Title != nil {
		media.Title = *req.Title
	}
	if req.Description != nil {
		media.Description = *req.Description
	}
	if req.Artists != nil {
		// Build Artist slice from names; repository will find-or-create.
		media.Artists = make([]models.Artist, 0, len(*req.Artists))
		for _, name := range *req.Artists {
			name = strings.TrimSpace(name)
			if name != "" {
				media.Artists = append(media.Artists, models.Artist{Name: name})
			}
		}
	}
	if req.Album != nil {
		media.Album = *req.Album
	}
	if req.Genre != nil {
		media.Genre = *req.Genre
	}
	if req.Year != nil {
		media.Year = *req.Year
	}

	if media.Metadata == nil {
		media.Metadata = &models.Metadata{}
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

	return c.JSON(media)
}
