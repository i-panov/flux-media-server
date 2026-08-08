package handlers

import (
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
)

type ArtistHandler struct {
	artistRepo repository.ArtistRepository
}

func NewArtistHandler(artistRepo repository.ArtistRepository) *ArtistHandler {
	return &ArtistHandler{artistRepo: artistRepo}
}

// List returns all artists ordered by name.
func (h *ArtistHandler) List(c *fiber.Ctx) error {
	ctx := c.UserContext()
	artists, err := h.artistRepo.FindAll(ctx)
	if err != nil {
		log.Printf("ArtistHandler.List: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch artists")
	}
	return c.JSON(fiber.Map{"items": artists})
}
