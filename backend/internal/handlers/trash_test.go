package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupTrashTestApp(t *testing.T) (*fiber.App, string, *gorm.DB) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	colRepo := repository.NewCollectionRepository(db)
	libraryPath := t.TempDir()

	trash := NewTrashHandler(
		mediaRepo,
		colRepo,
		&fakeStreamer{allowedPaths: []string{libraryPath}},
		services.NewThumbnailService(t.TempDir()),
	)
	mediaHandler := NewMediaHandler(mediaRepo, &fakeStreamer{allowedPaths: []string{libraryPath}}, services.NewThumbnailService(t.TempDir()))
	colHandler := NewCollectionHandler(colRepo, repository.NewCollectionItemRepository(db), mediaRepo)

	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})
	app.Post("/api/collections", colHandler.Create)
	app.Post("/api/media", mediaHandler.Create)
	app.Get("/api/media/:id", mediaHandler.Get)
	app.Delete("/api/media/:id", mediaHandler.Delete)
	app.Delete("/api/collections/:id", colHandler.Delete)
	app.Get("/api/collections/:id/stats", trash.Stats)
	app.Get("/api/trash", trash.List)
	app.Delete("/api/trash", trash.Empty)
	app.Post("/api/trash/media/:id/restore", trash.RestoreMedia)
	app.Delete("/api/trash/media/:id", trash.PurgeMedia)
	app.Post("/api/trash/collections/:id/restore", trash.RestoreCollection)
	app.Delete("/api/trash/collections/:id", trash.PurgeCollection)

	return app, libraryPath, db
}

func TestTrash_FullCycle(t *testing.T) {
	app, libraryPath, _ := setupTrashTestApp(t)

	// Медиа с реальным файлом в библиотеке.
	videoPath := filepath.Join(libraryPath, "film.mkv")
	require.NoError(t, os.WriteFile(videoPath, []byte("data"), 0644))
	body := `{"title":"Film","type":"video","file_path":"` + videoPath + `"}`
	req := httptest.NewRequest("POST", "/api/media", bytes.NewReader([]byte(body)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, 201, resp.StatusCode)

	// Коллекция с сезоном.
	colBody := `{"name":"Сериал","type":"video"}`
	req = httptest.NewRequest("POST", "/api/collections", bytes.NewReader([]byte(colBody)))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	require.Equal(t, 201, resp.StatusCode)
	var root models.Collection
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&root))

	// В корзину оба.
	req = httptest.NewRequest("DELETE", "/api/media/1", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(root.ID)), nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// Файл цел (корзина, не снос).
	_, err = os.Stat(videoPath)
	require.NoError(t, err, "trash keeps the file")

	// Список корзины: оба плоским списком.
	req = httptest.NewRequest("GET", "/api/trash", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	var trash TrashListResponse
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&trash))
	assert.Len(t, trash.Media, 1)
	assert.Len(t, trash.Collections, 1)

	// Живой GET медиа — 404.
	req = httptest.NewRequest("GET", "/api/media/1", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)

	// Восстановление медиа.
	req = httptest.NewRequest("POST", "/api/trash/media/1/restore", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	req = httptest.NewRequest("GET", "/api/media/1", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// Purge коллекции: второй purge — 404.
	req = httptest.NewRequest("DELETE", "/api/trash/collections/"+strconv.Itoa(int(root.ID)), nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/trash/collections/"+strconv.Itoa(int(root.ID)), nil))
	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)
}

func TestTrash_PurgeMediaRemovesFile(t *testing.T) {
	app, libraryPath, db := setupTrashTestApp(t)

	videoPath := filepath.Join(libraryPath, "gone.mkv")
	require.NoError(t, os.WriteFile(videoPath, []byte("data"), 0644))
	ctx := context.Background()

	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, mediaRepo.Create(ctx, &models.Media{
		Title: "Gone", Type: models.MediaTypeVideo, FilePath: videoPath,
	}))
	require.NoError(t, mediaRepo.Delete(ctx, 1))

	req := httptest.NewRequest("DELETE", "/api/trash/media/1", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	_, err = os.Stat(videoPath)
	assert.True(t, os.IsNotExist(err), "purge стирает файл с диска")
}

func TestTrash_Stats(t *testing.T) {
	app, _, db := setupTrashTestApp(t)

	mkCol := func(name string, parent *uint) uint {
		payload := `{"name":"` + name + `","type":"video"`
		if parent != nil {
			payload += `,"parent_id":` + strconv.Itoa(int(*parent))
		}
		payload += `}`
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader([]byte(payload)))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	root := mkCol("Сериал", nil)
	season := mkCol("S01", &root)

	mediaRepo := repository.NewMediaRepository(db)
	itemRepo := repository.NewCollectionItemRepository(db)
	ctx := context.Background()
	require.NoError(t, mediaRepo.Create(ctx, &models.Media{Title: "Ep1", Type: models.MediaTypeVideo, FilePath: "/e1.mkv"}))
	require.NoError(t, mediaRepo.Create(ctx, &models.Media{Title: "Ep2", Type: models.MediaTypeVideo, FilePath: "/e2.mkv"}))
	require.NoError(t, mediaRepo.Create(ctx, &models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: "/f.mkv"}))
	_, err := itemRepo.AddItemAtomic(ctx, season, 1)
	require.NoError(t, err)
	_, err = itemRepo.AddItemAtomic(ctx, season, 2)
	require.NoError(t, err)
	// Элемент самого корня тоже считается (иначе confirm занижает,
	// а purge сносит больше показанного).
	_, err = itemRepo.AddItemAtomic(ctx, root, 3)
	require.NoError(t, err)

	req := httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(root))+"/stats", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, 200, resp.StatusCode)
	var stats map[string]int64
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&stats))
	assert.Equal(t, int64(1), stats["subcollections"])
	assert.Equal(t, int64(3), stats["items"])
}
