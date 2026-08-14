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

func setupLyricsTestApp(t *testing.T) *fiber.App {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	lyricsRepo := repository.NewLyricsRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create test media
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Song",
		Type:     models.MediaTypeAudio,
		FilePath: "/test.mp3",
	}))

	handler := NewLyricsHandler(lyricsRepo, mediaRepo)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Get("/api/media/:id/lyrics", handler.GetLyrics)
	app.Put("/api/media/:id/lyrics", handler.UpsertLyrics)

	return app
}

func TestLyricsHandler_GetLyrics_NotFound(t *testing.T) {
	app := setupLyricsTestApp(t)

	req := httptest.NewRequest("GET", "/api/media/1/lyrics", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestLyricsHandler_UpsertMediaNotFound(t *testing.T) {
	app := setupLyricsTestApp(t)

	// Медиа 999 не существует — 404 до создания записи lyrics.
	body, _ := json.Marshal(map[string]string{"lyrics_text": "La la la"})
	req := httptest.NewRequest("PUT", "/api/media/999/lyrics", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestLyricsHandler_UpsertAndGetLyrics(t *testing.T) {
	app := setupLyricsTestApp(t)

	// Upsert lyrics
	body, _ := json.Marshal(map[string]string{
		"lyrics_text": "La la la",
		"translation": "Ля ля ля",
		"source":      "manual",
	})
	req := httptest.NewRequest("PUT", "/api/media/1/lyrics", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Get lyrics
	req = httptest.NewRequest("GET", "/api/media/1/lyrics", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var lyrics models.Lyrics
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &lyrics)
	assert.Equal(t, "La la la", lyrics.LyricsText)
	assert.Equal(t, "Ля ля ля", lyrics.Translation)
}
