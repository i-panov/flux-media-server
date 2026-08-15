package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
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

func (f *fakeStreamer) ResolveStreamPath(_ context.Context, filePath string) (bool, string, error) {
	allowed, err := f.IsPathAllowed(nil, filePath)
	return allowed, filePath, err
}

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
	app.Get("/api/media/bulk", handler.Bulk)
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

func TestMediaHandler_Bulk(t *testing.T) {
	app, libraryPath := setupMediaTestApp(t)

	// Создаём медиа через API (пути — внутри библиотеки, иначе Create
	// ответит 403).
	for i := 1; i <= 3; i++ {
		body, _ := json.Marshal(map[string]interface{}{
			"title":     fmt.Sprintf("Movie %d", i),
			"type":      string(models.MediaTypeVideo),
			"file_path": filepath.Join(libraryPath, "movie.mkv"),
		})
		req := httptest.NewRequest("POST", "/api/media", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, fiber.StatusCreated, resp.StatusCode)
	}

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/bulk?ids=1,2,2,3", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var out struct {
		Items []models.Media `json:"items"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	require.Len(t, out.Items, 3, "duplicates must be removed")

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/bulk?ids=1,99", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	out.Items = nil
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	require.Len(t, out.Items, 1, "missing ids are skipped")

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/bulk?ids=99", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	out.Items = nil
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	require.Empty(t, out.Items)
}

func TestMediaHandler_BulkInvalidIDs(t *testing.T) {
	app, _ := setupMediaTestApp(t)

	for _, q := range []string{"", "ids=", "ids=abc", "ids=1,abc", "ids=0", "ids=-1", "ids=1.5"} {
		url := "/api/media/bulk"
		if q != "" {
			url += "?" + q
		}
		resp, err := app.Test(httptest.NewRequest("GET", url, nil))
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "query %q must be rejected", q)
	}

	tooMany := "ids=" + strings.TrimSuffix(strings.Repeat("1,", 101), ",")
	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/bulk?"+tooMany, nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "more than max ids must be rejected")
}

// setupStreamTestApp строит приложение с настоящим StreamerService и
// media-записью, указывающей на filePath (файл может не существовать).
func setupStreamTestApp(t *testing.T, libraryPath, filePath string) *fiber.App {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Stream Me",
		Type:     models.MediaTypeVideo,
		FilePath: filePath,
	}))

	cfg := &config.Config{Media: config.MediaConfig{VideoPath: libraryPath}}
	streamer := services.NewStreamerService(cfg)
	handler := NewMediaHandler(mediaRepo, streamer, services.NewThumbnailService(t.TempDir()))
	app := fiber.New()
	app.Get("/api/media/:id/stream", handler.Stream)
	return app
}

func TestMediaHandler_StreamFile(t *testing.T) {
	libDir := t.TempDir()
	filePath := filepath.Join(libDir, "movie.mp4")
	content := []byte("fake mp4 content")
	require.NoError(t, os.WriteFile(filePath, content, 0644))

	app := setupStreamTestApp(t, libDir, filePath)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/stream", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "video/mp4", resp.Header.Get("Content-Type"))

	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, content, body)
}

func TestMediaHandler_StreamMissingFile(t *testing.T) {
	libDir := t.TempDir()
	filePath := filepath.Join(libDir, "gone.mp4")

	app := setupStreamTestApp(t, libDir, filePath)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/stream", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	// Путь ФС не должен утекать в ответ.
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.NotContains(t, string(body), libDir)
	assert.NotContains(t, string(body), "gone.mp4")
}

func TestMediaHandler_StreamDenied(t *testing.T) {
	libDir := t.TempDir()
	// Файл вне зарегистрированной библиотеки.
	outsideDir := t.TempDir()
	filePath := filepath.Join(outsideDir, "secret.mp4")
	require.NoError(t, os.WriteFile(filePath, []byte("secret"), 0644))

	app := setupStreamTestApp(t, libDir, filePath)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/stream", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}
