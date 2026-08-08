package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type FavoriteHandler struct {
	favRepo    repository.FavoriteRepository
	mediaRepo  repository.MediaRepository
	artistRepo repository.ArtistRepository
}

func NewFavoriteHandler(favRepo repository.FavoriteRepository, mediaRepo repository.MediaRepository, artistRepo repository.ArtistRepository) *FavoriteHandler {
	return &FavoriteHandler{favRepo: favRepo, mediaRepo: mediaRepo, artistRepo: artistRepo}
}

// AddFavorite adds a media item to the user's favorites.
func (h *FavoriteHandler) AddFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Verify media exists
	if _, err := h.mediaRepo.FindByID(ctx, uint(mediaID)); err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	mediaIDUint := uint(mediaID)
	fav := &models.Favorite{
		UserID:  userID,
		MediaID: &mediaIDUint,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// RemoveFavorite removes a media item from the user's favorites.
func (h *FavoriteHandler) RemoveFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	if err := h.favRepo.Delete(ctx, userID, uint(mediaID)); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Favorite not found")
		}
		log.Printf("Delete favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove favorite")
	}

	return c.JSON(fiber.Map{"message": "Favorite removed"})
}

// ListFavorites returns the user's favorites, optionally filtered by type.
func (h *FavoriteHandler) ListFavorites(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	limit := c.QueryInt("limit", 50)
	offset := c.QueryInt("offset", 0)
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	ctx := c.UserContext()
	favs, total, err := h.favRepo.FindByUser(ctx, userID, limit, offset)
	if err != nil {
		log.Printf("FindByUser favorites: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch favorites")
	}

	return c.JSON(fiber.Map{
		"items":  favs,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// AddArtistFavorite adds an artist to the user's favorites.
func (h *FavoriteHandler) AddArtistFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	var req struct {
		ArtistID uint `json:"artist_id"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.ArtistID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "artist_id is required")
	}

	ctx := c.UserContext()

	artistID := req.ArtistID
	fav := &models.Favorite{
		UserID:   userID,
		ArtistID: &artistID,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create artist favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add artist favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// RemoveArtistFavorite removes an artist from the user's favorites.
func (h *FavoriteHandler) RemoveArtistFavorite(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	artistID := c.QueryInt("artist_id")
	if artistID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "artist_id query parameter is required")
	}

	ctx := c.UserContext()

	if err := h.favRepo.DeleteArtist(ctx, userID, uint(artistID)); err != nil {
		log.Printf("DeleteArtist favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove artist favorite")
	}

	return c.JSON(fiber.Map{"message": "Artist favorite removed"})
}
