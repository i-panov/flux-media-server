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

func setupMetadataTestApp(t *testing.T) *fiber.App {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))

	handler := NewMetadataHandler(mediaRepo)
	app := fiber.New()

	app.Put("/api/metadata/:mediaId", handler.Update)
	app.Post("/api/metadata/:mediaId/refresh", handler.Refresh)

	return app
}

func TestMetadataHandler_UpdateInvalidYear(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]int{"year": 1500})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMetadataHandler_UpdateFutureYearTooFar(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]int{"year": 9999})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMetadataHandler_UpdateInvalidRating(t *testing.T) {
	app := setupMetadataTestApp(t)

	for _, rating := range []float64{-1, 11, 10.5} {
		body, _ := json.Marshal(map[string]float64{"rating": rating})
		req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "rating %v must be rejected", rating)
	}
}

func TestMetadataHandler_UpdateValid(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]interface{}{"year": 2001, "rating": 8.5})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}
