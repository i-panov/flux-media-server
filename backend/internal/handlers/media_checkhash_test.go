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

// Регрессия: CheckHash отвечал exists:true на неизвестный хэш, потому что
// FindByHash возвращает не-nil пустую структуру вместе с
// ErrRecordNotFound, а хендлер проверял только existing != nil.
// Итог: любая загрузка нового файла упиралась в «уже есть на сервере».
func TestMediaHandler_CheckHashUnknownIsNotDuplicate(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	handler := NewMediaHandler(mediaRepo, &fakeStreamer{}, nil)
	app := fiber.New()
	app.Post("/api/media/check-hash", handler.CheckHash)

	post := func(hash string) map[string]any {
		body, _ := json.Marshal(map[string]string{"hash": hash})
		req := httptest.NewRequest("POST", "/api/media/check-hash", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, fiber.StatusOK, resp.StatusCode)
		var out map[string]any
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
		return out
	}

	// Пустая база: неизвестный хэш — не дубликат.
	assert.Equal(t, false, post("0fbd5baf690d")["exists"])

	// Известный хэш — дубликат с живой строкой.
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title: "T", Type: models.MediaTypeVideo, FilePath: "/a.mkv", FileHash: "0fbd5baf690d",
	}))
	out := post("0fbd5baf690d")
	assert.Equal(t, true, out["exists"])
	assert.Equal(t, false, out["trashed"])

	// Trashed-строка: дубликат с флагом для восстановления.
	require.NoError(t, mediaRepo.Delete(context.Background(), 1))
	out = post("0fbd5baf690d")
	assert.Equal(t, true, out["exists"])
	assert.Equal(t, true, out["trashed"])
}
