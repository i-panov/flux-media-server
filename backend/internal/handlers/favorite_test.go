package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupFavoriteTestApp(t *testing.T) *fiber.App {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	favRepo := repository.NewFavoriteRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	artistRepo := repository.NewArtistRepository(db)

	// Создаём пользователя и медиа — FK constraints требуют их наличия.
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))

	// Create a test artist
	artist, err := artistRepo.FindOrCreateByName(context.Background(), "Pink Floyd")
	require.NoError(t, err)

	handler := NewFavoriteHandler(favRepo, mediaRepo, artistRepo)
	app := fiber.New()

	// Simulate authenticated user
	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Use(func(c *fiber.Ctx) error {
		// Store artist ID in locals for test access
		c.Locals("test_artist_id", artist.ID)
		return c.Next()
	})

	app.Post("/api/media/:id/favorite", handler.AddFavorite)
	app.Delete("/api/media/:id/favorite", handler.RemoveFavorite)
	app.Get("/api/favorites", handler.ListFavorites)
	app.Post("/api/favorites/artist", handler.AddArtistFavorite)
	app.Delete("/api/favorites/artist", handler.RemoveArtistFavorite)

	return app
}

func TestFavoriteHandler_AddFavorite(t *testing.T) {
	app := setupFavoriteTestApp(t)

	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestFavoriteHandler_AddFavoriteDuplicate(t *testing.T) {
	app := setupFavoriteTestApp(t)

	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	// Дубликат — 409.
	req = httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestFavoriteHandler_RemoveFavorite(t *testing.T) {
	app := setupFavoriteTestApp(t)

	// Add first
	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	_, err := app.Test(req)
	require.NoError(t, err)

	// Remove
	req = httptest.NewRequest("DELETE", "/api/media/1/favorite", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestFavoriteHandler_ListFavorites(t *testing.T) {
	app := setupFavoriteTestApp(t)

	// Add a favorite
	req := httptest.NewRequest("POST", "/api/media/1/favorite", nil)
	_, err := app.Test(req)
	require.NoError(t, err)

	// List
	req = httptest.NewRequest("GET", "/api/favorites?type=video", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var result struct {
		Items []models.Favorite `json:"items"`
		Total int64             `json:"total"`
	}
	body := bytes.Buffer{}
	body.ReadFrom(resp.Body)
	json.Unmarshal(body.Bytes(), &result)
	assert.Len(t, result.Items, 1)
	assert.Equal(t, int64(1), result.Total)
}

func TestFavoriteHandler_AddArtistFavorite(t *testing.T) {
	app := setupFavoriteTestApp(t)

	// Artist ID 1 = "Pink Floyd", created in setup.
	body, _ := json.Marshal(map[string]uint{"artist_id": 1})
	req := httptest.NewRequest("POST", "/api/favorites/artist", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestFavoriteHandler_RemoveArtistFavorite(t *testing.T) {
	app := setupFavoriteTestApp(t)

	// Add artist favorite (artist ID 1 = "Pink Floyd")
	body, _ := json.Marshal(map[string]uint{"artist_id": 1})
	req := httptest.NewRequest("POST", "/api/favorites/artist", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	_, err := app.Test(req)
	require.NoError(t, err)

	// Remove
	req = httptest.NewRequest("DELETE", "/api/favorites/artist?artist_id=1", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestFavoriteHandler_ListEmptyItems(t *testing.T) {
	app := setupFavoriteTestApp(t)

	// Без добавленных избранных список сериализуется как [], а не null.
	resp, err := app.Test(httptest.NewRequest("GET", "/api/favorites", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	assert.Contains(t, buf.String(), `"items":[]`)
}
