package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

// fakeStreamer — реализация StreamerInterface для тестов: разрешает пути
// внутри allowedPaths, файлы вне списка считает недопустимыми.
type fakeStreamer struct {
	allowedPaths []string
}

func (f *fakeStreamer) IsPathAllowed(_ context.Context, filePath string) (bool, error) {
	for _, p := range f.allowedPaths {
		if strings.HasPrefix(filePath, p) {
			return true, nil
		}
	}
	return false, nil
}

func (f *fakeStreamer) Stream(_ *fiber.Ctx, _ string) error { return nil }

func setupMediaTestApp(t *testing.T) (*fiber.App, string) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	libraryPath := t.TempDir()
	require.NoError(t, os.MkdirAll(libraryPath, 0755))

	handler := NewMediaHandler(mediaRepo, &fakeStreamer{allowedPaths: []string{libraryPath}}, services.NewThumbnailService(t.TempDir()))
	app := fiber.New()
	app.Get("/api/media", handler.List)
	app.Get("/api/media/:id", handler.Get)
	app.Post("/api/media", handler.Create)
	app.Put("/api/media/:id", handler.Update)
	app.Delete("/api/media/:id", handler.Delete)

	return app, libraryPath
}

func createTestMedia(t *testing.T, app *fiber.App, libraryPath string, filename string) {
	t.Helper()
	body, _ := json.Marshal(map[string]interface{}{
		"title":     "Test Movie",
		"type":      string(models.MediaTypeVideo),
		"file_path": filepath.Join(libraryPath, filename),
	})
	req := httptest.NewRequest("POST", "/api/media", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestMediaHandler_ListEmptyItems(t *testing.T) {
	app, _ := setupMediaTestApp(t)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	// Пустой список сериализуется как [], а не null.
	assert.Contains(t, buf.String(), `"items":[]`)
}

func TestMediaHandler_ListInvalidYear(t *testing.T) {
	app, _ := setupMediaTestApp(t)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media?year=abc", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMediaHandler_GetInvalidID(t *testing.T) {
	app, _ := setupMediaTestApp(t)

	// Отрицательный id не должен превращаться в огромный uint.
	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/-1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/not-a-number", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMediaHandler_UpdateRequiresType(t *testing.T) {
	app, libraryPath := setupMediaTestApp(t)
	createTestMedia(t, app, libraryPath, "movie.mkv")

	// Обновление без type — 400: пустой type не должен затирать/игнорировать
	// тип медиа.
	body, _ := json.Marshal(map[string]interface{}{
		"title":     "New Title",
		"file_path": filepath.Join(libraryPath, "movie.mkv"),
	})
	req := httptest.NewRequest("PUT", "/api/media/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	// Невалидный type — тоже 400.
	body, _ = json.Marshal(map[string]interface{}{
		"title":     "New Title",
		"type":      "garbage",
		"file_path": filepath.Join(libraryPath, "movie.mkv"),
	})
	req = httptest.NewRequest("PUT", "/api/media/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMediaHandler_UpdateValid(t *testing.T) {
	app, libraryPath := setupMediaTestApp(t)
	createTestMedia(t, app, libraryPath, "movie.mkv")

	body, _ := json.Marshal(map[string]interface{}{
		"title":     "Updated Title",
		"type":      string(models.MediaTypeAudio),
		"file_path": filepath.Join(libraryPath, "movie.mkv"),
	})
	req := httptest.NewRequest("PUT", "/api/media/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var media models.Media
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &media))
	assert.Equal(t, "Updated Title", media.Title)
	assert.Equal(t, models.MediaTypeAudio, media.Type)
}

func TestMediaHandler_DeleteOutsideLibrary(t *testing.T) {
	// Медиа с путём вне зарегистрированных библиотек: файл не удаляется,
	// запись удаляется.
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)

	outsidePath := filepath.Join(t.TempDir(), "outside.mkv")
	require.NoError(t, os.WriteFile(outsidePath, []byte("data"), 0644))

	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Outside",
		Type:     models.MediaTypeVideo,
		FilePath: outsidePath,
	}))

	handler := NewMediaHandler(mediaRepo, &fakeStreamer{allowedPaths: []string{}}, services.NewThumbnailService(t.TempDir()))
	app := fiber.New()
	app.Delete("/api/media/:id", handler.Delete)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Файл вне библиотеки должен остаться на диске.
	_, err = os.Stat(outsidePath)
	require.NoError(t, err, "file outside libraries must not be removed")

	// Запись при этом удалена.
	_, err = mediaRepo.FindByID(context.Background(), 1)
	require.Error(t, err)
}

func TestMediaHandler_DeleteInsideLibrary(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)

	libraryPath := t.TempDir()
	insidePath := filepath.Join(libraryPath, "inside.mkv")
	require.NoError(t, os.WriteFile(insidePath, []byte("data"), 0644))

	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Inside",
		Type:     models.MediaTypeVideo,
		FilePath: insidePath,
	}))

	handler := NewMediaHandler(mediaRepo, &fakeStreamer{allowedPaths: []string{libraryPath}}, services.NewThumbnailService(t.TempDir()))
	app := fiber.New()
	app.Delete("/api/media/:id", handler.Delete)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Файл внутри библиотеки удаляется.
	_, err = os.Stat(insidePath)
	require.True(t, os.IsNotExist(err))
}
