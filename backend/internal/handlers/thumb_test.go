package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupThumbTestApp(t *testing.T) *fiber.App {
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

	thumbSvc := services.NewThumbnailService(t.TempDir())
	handler := NewThumbHandler(mediaRepo, thumbSvc)

	app := fiber.New(fiber.Config{BodyLimit: 20 << 20})
	app.Put("/api/media/:id/cover", handler.UploadCover)
	app.Get("/api/media/:id/cover", handler.GetCover)

	return app
}

func coverMultipartForm(t *testing.T, filename string, content []byte) (*bytes.Buffer, string) {
	t.Helper()
	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("cover", filename)
	require.NoError(t, err)
	_, err = part.Write(content)
	require.NoError(t, err)
	require.NoError(t, writer.Close())
	return body, writer.FormDataContentType()
}

func TestThumbHandler_UploadCoverValidJPEG(t *testing.T) {
	app := setupThumbTestApp(t)

	// Минимальный валидный JPEG-заголовок: magic FF D8 FF + маркер JFIF
	// (не менее 12 байт).
	content := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 'J', 'F', 'I', 'F', 0x00, 0x01}
	body, contentType := coverMultipartForm(t, "cover.jpg", content)

	req := httptest.NewRequest("PUT", "/api/media/1/cover", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var parsed map[string]string
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &parsed))
	assert.Equal(t, "/api/media/1/cover", parsed["cover_url"])
}

func TestThumbHandler_UploadCoverTooSmall(t *testing.T) {
	app := setupThumbTestApp(t)

	// 3 байта "FF D8 FF" — фрагмент magic, но не валидный JPEG.
	content := []byte{0xFF, 0xD8, 0xFF}
	body, contentType := coverMultipartForm(t, "cover.jpg", content)

	req := httptest.NewRequest("PUT", "/api/media/1/cover", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestThumbHandler_UploadCoverInvalidMagicBytes(t *testing.T) {
	app := setupThumbTestApp(t)

	// Расширение .jpg, но содержимое — не изображение.
	content := []byte("this is definitely not an image")
	body, contentType := coverMultipartForm(t, "cover.jpg", content)

	req := httptest.NewRequest("PUT", "/api/media/1/cover", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestThumbHandler_UploadCoverMediaNotFound(t *testing.T) {
	app := setupThumbTestApp(t)

	content := []byte{0xFF, 0xD8, 0xFF, 0xE0}
	body, contentType := coverMultipartForm(t, "cover.jpg", content)

	req := httptest.NewRequest("PUT", "/api/media/999/cover", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}
