package handlers_test

import (
	"bytes"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupUploadTest(t *testing.T) (*fiber.App, repository.MediaRepository, func()) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)

	err = repository.AutoMigrate(db)
	require.NoError(t, err)

	mediaRepo := repository.NewMediaRepository(db)

	tempDir := t.TempDir()
	libraryPath := filepath.Join(tempDir, "library")
	err = os.MkdirAll(libraryPath, 0755)
	require.NoError(t, err)

	thumbDir := filepath.Join(tempDir, "thumbnails")
	err = os.MkdirAll(thumbDir, 0755)
	require.NoError(t, err)
	thumbSvc := services.NewThumbnailService(thumbDir)

	app := fiber.New(fiber.Config{
		BodyLimit: 5 * 1024 * 1024,
	})

	mediaCfg := config.MediaConfig{
		VideoPath:     libraryPath,
		ThumbnailPath: thumbDir,
	}
	cfg := handlers.UploadConfig{
		MaxFileSize: 10 * 1024 * 1024,
	}
	handler := handlers.NewUploadHandler(mediaRepo, nil, thumbSvc, mediaCfg, cfg)

	app.Post("/api/media/upload", handler.Upload)

	return app, mediaRepo, func() {
		db.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}
}

func createMultipartForm(t *testing.T, filename string, content []byte, mediaType string) (*bytes.Buffer, string) {
	t.Helper()

	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)

	err := writer.WriteField("media_type", mediaType)
	require.NoError(t, err)

	part, err := writer.CreateFormFile("file", filename)
	require.NoError(t, err)
	_, err = part.Write(content)
	require.NoError(t, err)

	err = writer.Close()
	require.NoError(t, err)

	return body, writer.FormDataContentType()
}

func TestUploadSuccess(t *testing.T) {
	app, _, cleanup := setupUploadTest(t)
	defer cleanup()

	fileContent := []byte("test file content")
	body, contentType := createMultipartForm(t, "test.mp4", fileContent, string(models.MediaTypeVideo))

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestUploadMissingFile(t *testing.T) {
	app, _, cleanup := setupUploadTest(t)
	defer cleanup()

	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	err := writer.WriteField("media_type", string(models.MediaTypeVideo))
	require.NoError(t, err)
	err = writer.Close()
	require.NoError(t, err)

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestUploadFileTooLarge(t *testing.T) {
	app, _, cleanup := setupUploadTest(t)
	defer cleanup()

	fileContent := make([]byte, 7*1024*1024)
	body, contentType := createMultipartForm(t, "large.mp4", fileContent, string(models.MediaTypeVideo))

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	_, err := app.Test(req, 10000)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "body size exceeds the given limit")
}
