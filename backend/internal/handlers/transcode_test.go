package handlers_test

import (
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/handlers"
	"flux/internal/services"
)

func TestTranscodeStatus(t *testing.T) {
	stub := &stubTranscodeQueue{
		status:   services.TranscodeJobStatus{Status: services.TranscodeTaskProcessing, Progress: 42, Speed: 1.5},
		statusOK: true,
	}
	app := fiber.New()
	handler := handlers.NewTranscodeHandler(nil, stub)
	app.Get("/api/media/transcodes/:id", handler.TranscodeStatus)
	app.Delete("/api/media/transcodes/:id", handler.TranscodeCancel)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/transcodes/3", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/transcodes/abc", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestTranscodeStatusNotFound(t *testing.T) {
	stub := &stubTranscodeQueue{}
	app := fiber.New()
	handler := handlers.NewTranscodeHandler(nil, stub)
	app.Get("/api/media/transcodes/:id", handler.TranscodeStatus)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/transcodes/999", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestTranscodeCancel(t *testing.T) {
	stub := &stubTranscodeQueue{}
	app := fiber.New()
	handler := handlers.NewTranscodeHandler(nil, stub)
	app.Delete("/api/media/transcodes/:id", handler.TranscodeCancel)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/transcodes/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)
	assert.Equal(t, []uint64{5}, stub.cancelled)
}

func TestTranscodeCancelConflict(t *testing.T) {
	// Гонка проиграна (строка уже ушла из-под ног) — 409 с понятным
	// текстом, а не 500.
	stub := &stubTranscodeQueue{cancelErr: services.ErrTranscodeConflict}
	app := fiber.New()
	handler := handlers.NewTranscodeHandler(nil, stub)
	app.Delete("/api/media/transcodes/:id", handler.TranscodeCancel)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/transcodes/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}
