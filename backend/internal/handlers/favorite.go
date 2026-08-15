package handlers

import (
	"errors"
	"log"
	"strings"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

// defaultPageSize — размер страницы по умолчанию (favorites, progress).
const defaultPageSize = 50

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
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Verify media exists
	if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	fav := &models.Favorite{
		UserID:  userID,
		MediaID: &mediaID,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create favorite: %v", err)
		// UNIQUE violation on (user_id, media_id) means already favorited.
		if isUniqueViolation(err) {
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"message": "Already in favorites",
			})
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// RemoveFavorite removes a media item from the user's favorites.
func (h *FavoriteHandler) RemoveFavorite(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	if err := h.favRepo.Delete(ctx, userID, mediaID); err != nil {
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
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	mediaType := c.Query("type")
	if mediaType != "" && !isValidMediaType(mediaType) {
		return response.Error(c, fiber.StatusBadRequest, "invalid type")
	}

	limit, offset := response.ClampPage(c.QueryInt("limit", defaultPageSize), c.QueryInt("offset", 0), defaultPageSize)

	ctx := c.UserContext()
	favs, total, err := h.favRepo.FindByUser(ctx, userID, mediaType, limit, offset)
	if err != nil {
		log.Printf("FindByUser favorites: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch favorites")
	}
	if favs == nil {
		favs = []models.Favorite{}
	}

	return response.Paginated(c, favs, total, limit, offset)
}

// AddArtistFavorite adds an artist to the user's favorites.
func (h *FavoriteHandler) AddArtistFavorite(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
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

	// Verify the artist exists before creating the favorite.
	if _, err := h.artistRepo.FindByID(ctx, req.ArtistID); err != nil {
		return repoError(c, err, "Artist not found", "Failed to add artist favorite")
	}

	artistID := req.ArtistID
	fav := &models.Favorite{
		UserID:   userID,
		ArtistID: &artistID,
	}

	if err := h.favRepo.Create(ctx, fav); err != nil {
		log.Printf("Create artist favorite: %v", err)
		if isUniqueViolation(err) {
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"message": "Already in favorites",
			})
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add artist favorite")
	}

	return c.Status(fiber.StatusCreated).JSON(fav)
}

// isUniqueViolation проверяет, что ошибка — именно нарушение уникального
// индекса favorites (по медиа или артисту), а не иной UNIQUE-конфликт.
// Проверка по колонкам вместо широкого "UNIQUE": сообщение SQLite
// содержит имена колонок, а не имя индекса.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	if !strings.Contains(msg, "UNIQUE constraint failed") {
		return false
	}
	return strings.Contains(msg, "favorites.user_id") &&
		(strings.Contains(msg, "favorites.media_id") || strings.Contains(msg, "favorites.artist_id"))
}

// RemoveArtistFavorite removes an artist from the user's favorites.
func (h *FavoriteHandler) RemoveArtistFavorite(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	artistID := c.QueryInt("artist_id")
	if artistID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "artist_id query parameter is required")
	}

	ctx := c.UserContext()

	if err := h.favRepo.DeleteArtist(ctx, userID, uint(artistID)); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Artist favorite not found")
		}
		log.Printf("DeleteArtist favorite: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove artist favorite")
	}

	return c.JSON(fiber.Map{"message": "Artist favorite removed"})
}
