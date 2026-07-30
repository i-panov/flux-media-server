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

	"flux/internal/handlers"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupUploadTest(t *testing.T) (*fiber.App, repository.LibraryRepository, repository.MediaRepository, func()) {
	t.Helper()

	// Create test database
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)

	// Run migrations
	err = repository.AutoMigrate(db)
	require.NoError(t, err)

	// Create repositories
	libraryRepo := repository.NewLibraryRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create temp directories
	tempDir := t.TempDir()
	libraryPath := filepath.Join(tempDir, "library")
	err = os.MkdirAll(libraryPath, 0755)
	require.NoError(t, err)

	// Create test library
	library := &models.MediaLibrary{
		Name:    "Test Library",
		Path:    libraryPath,
		Type:    "video",
		Enabled: true,
	}
	err = libraryRepo.Create(context.Background(), library)
	require.NoError(t, err)

	// Create Fiber app with a smaller body limit to make testing easier
	app := fiber.New(fiber.Config{
		BodyLimit: 5 * 1024 * 1024, // 5MB - smaller than our test file
	})

	// Create thumbnail service
	thumbDir := filepath.Join(tempDir, "thumbnails")
	err = os.MkdirAll(thumbDir, 0755)
	require.NoError(t, err)
	thumbSvc := services.NewThumbnailService(thumbDir)

	// Create upload handler
	cfg := handlers.UploadConfig{
		MaxFileSize: 10 * 1024 * 1024, // 10MB - larger than Fiber's limit
	}
	handler := handlers.NewUploadHandler(libraryRepo, mediaRepo, nil, thumbSvc, cfg)

	// Register route
	app.Post("/api/media/upload", handler.Upload)

	return app, libraryRepo, mediaRepo, func() {
		// Cleanup function
		db.Exec("PRAGMA wal_checkpoint(TRUNCATE)")
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}
}

func createMultipartForm(t *testing.T, filename string, content []byte, libraryID string) (*bytes.Buffer, string) {
	t.Helper()

	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)

	// Add library_id field
	err := writer.WriteField("library_id", libraryID)
	require.NoError(t, err)

	// Add file field
	part, err := writer.CreateFormFile("file", filename)
	require.NoError(t, err)
	_, err = part.Write(content)
	require.NoError(t, err)

	err = writer.Close()
	require.NoError(t, err)

	return body, writer.FormDataContentType()
}

func TestUploadSuccess(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t)
	defer cleanup()

	// Create test file content
	fileContent := []byte("test file content")
	body, contentType := createMultipartForm(t, "test.mp4", fileContent, "1")

	// Create request
	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	// Perform request
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestUploadMissingFile(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t)
	defer cleanup()

	// Create multipart form without file
	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	err := writer.WriteField("library_id", "1")
	require.NoError(t, err)
	err = writer.Close()
	require.NoError(t, err)

	// Create request
	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	// Perform request
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestUploadInvalidLibraryID(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t)
	defer cleanup()

	// Create test file content
	fileContent := []byte("test file content")
	body, contentType := createMultipartForm(t, "test.mp4", fileContent, "invalid")

	// Create request
	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	// Perform request
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestUploadFileTooLarge(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t)
	defer cleanup()

	// Create test file content that exceeds Fiber's body limit (7MB > 5MB limit)
	fileContent := make([]byte, 7*1024*1024)
	body, contentType := createMultipartForm(t, "large.mp4", fileContent, "1")

	// Create request
	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	// Perform request - this should fail before reaching our handler
	_, err := app.Test(req, 10000) // Increase timeout for large file
	require.Error(t, err)
	// The error should indicate the body size exceeded the limit
	assert.Contains(t, err.Error(), "body size exceeds the given limit")
}
