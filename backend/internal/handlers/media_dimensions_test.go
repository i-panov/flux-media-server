package handlers

import (
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

// Размеры кадра едут в API: клиент по соотношению сторон выбирает
// ориентацию fullscreen и пропорции встроенного превью ещё ДО старта
// воспроизведения. Если поля исчезнут из ответа — плеер молча откатится
// на жёсткие 16:9, и это будет выглядеть как «ориентация сломалась».
func TestMediaHandler_GetExposesVideoDimensions(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	handler := NewMediaHandler(mediaRepo, &fakeStreamer{}, nil)
	app := fiber.New()
	app.Get("/api/media/:id", handler.Get)

	video := &models.Media{
		Title: "Landscape", Type: models.MediaTypeVideo, FilePath: "/a.mkv",
		Width: 1920, Height: 1080,
	}
	require.NoError(t, mediaRepo.Create(context.Background(), video))

	req := httptest.NewRequest("GET", "/api/media/1", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var out struct {
		Width  int `json:"width"`
		Height int `json:"height"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	assert.Equal(t, 1920, out.Width)
	assert.Equal(t, 1080, out.Height)
}
