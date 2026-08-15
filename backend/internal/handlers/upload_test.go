package handlers_test

import (
	"bytes"
	"context"
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
		VideoPath:     filepath.Join(libraryPath, "video"),
		AudioPath:     filepath.Join(libraryPath, "audio"),
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

func TestUploadInvalidMediaType(t *testing.T) {
	app, _, cleanup := setupUploadTest(t)
	defer cleanup()

	// Невалидный media_type должен вернуть 400, а не молча стать video.
	fileContent := []byte("test file content")
	body, contentType := createMultipartForm(t, "test.mp4", fileContent, "garbage")

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

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

func TestUploadDuplicateFile(t *testing.T) {
	app, _, cleanup := setupUploadTest(t)
	defer cleanup()

	fileContent := []byte("duplicate content")
	body, contentType := createMultipartForm(t, "dup.mp4", fileContent, string(models.MediaTypeVideo))

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	// Тот же контент — тот же хэш: дубликат → 409, а не 500.
	body, contentType = createMultipartForm(t, "dup.mp4", fileContent, string(models.MediaTypeVideo))
	req = httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestUploadMediaTypeFromForm(t *testing.T) {
	app, mediaRepo, cleanup := setupUploadTest(t)
	defer cleanup()

	// media_type=audio задан явно: в Type записи сохраняется именно он,
	// а не определение по расширению (.mp4 → video).
	fileContent := []byte("audio content")
	body, contentType := createMultipartForm(t, "song.mp4", fileContent, string(models.MediaTypeAudio))

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	mediaList, _, err := mediaRepo.FindAll(context.Background(), nil, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	assert.Equal(t, models.MediaTypeAudio, mediaList[0].Type)
}

func TestUploadMediaTypeByExtension(t *testing.T) {
	app, mediaRepo, cleanup := setupUploadTest(t)
	defer cleanup()

	// media_type не задан: тип определяется по расширению (.mp3 → audio).
	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "song.mp3")
	require.NoError(t, err)
	_, err = part.Write([]byte("audio content"))
	require.NoError(t, err)
	require.NoError(t, writer.Close())

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	mediaList, _, err := mediaRepo.FindAll(context.Background(), nil, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	assert.Equal(t, models.MediaTypeAudio, mediaList[0].Type)
}
