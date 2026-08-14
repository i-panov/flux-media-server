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

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
)

func setupProgressTestApp(t *testing.T) *fiber.App {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	progressRepo := repository.NewProgressRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Пользователь и медиа нужны для FK constraints.
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))

	handler := NewProgressHandler(progressRepo, mediaRepo)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, uint(1))
		return c.Next()
	})

	app.Get("/api/progress", handler.List)
	app.Put("/api/progress/:mediaId", handler.Update)
	app.Delete("/api/progress/:mediaId", handler.Delete)

	return app
}

func TestProgressHandler_UpdateStoresDurationAndCompleted(t *testing.T) {
	app := setupProgressTestApp(t)

	body, _ := json.Marshal(map[string]interface{}{
		"position":  120,
		"duration":  5400,
		"completed": true,
	})
	req := httptest.NewRequest("PUT", "/api/progress/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var progress models.WatchProgress
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &progress))
	assert.Equal(t, 120, progress.Position)
	assert.Equal(t, 5400, progress.Duration)
	assert.True(t, progress.Completed)

	// Прогресс должен появиться в списке.
	req = httptest.NewRequest("GET", "/api/progress", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestProgressHandler_UpdateMediaNotFound(t *testing.T) {
	app := setupProgressTestApp(t)

	body, _ := json.Marshal(map[string]int{"position": 10})
	req := httptest.NewRequest("PUT", "/api/progress/999", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestProgressHandler_UpdateNegativePosition(t *testing.T) {
	app := setupProgressTestApp(t)

	body, _ := json.Marshal(map[string]int{"position": -5})
	req := httptest.NewRequest("PUT", "/api/progress/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}
