package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupCollectionTestApp(t *testing.T) *fiber.App {
	// Файловая БД, а не :memory:: параллельные запросы получают разные
	// коннекты пула, а каждая in-memory БД была бы пустой и без таблиц.
	db, err := repository.InitDB(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	colRepo := repository.NewCollectionRepository(db)
	itemRepo := repository.NewCollectionItemRepository(db)
	mediaRepo := repository.NewMediaRepository(db)

	// Create test media
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie 2",
		Type:     models.MediaTypeVideo,
		FilePath: "/test2.mkv",
	}))
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie 3",
		Type:     models.MediaTypeVideo,
		FilePath: "/test3.mkv",
	}))

	handler := NewCollectionHandler(colRepo, itemRepo, mediaRepo)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals("user_id", uint(1))
		return c.Next()
	})

	app.Post("/api/collections", handler.Create)
	app.Get("/api/collections", handler.List)
	app.Put("/api/collections/:id", handler.Update)
	app.Delete("/api/collections/:id", handler.Delete)
	app.Post("/api/collections/:id/items", handler.AddItem)
	app.Delete("/api/collections/:id/items/:mediaId", handler.RemoveItem)
	app.Get("/api/collections/:id/items", handler.ListItems)

	return app
}

func TestCollectionHandler_Create(t *testing.T) {
	app := setupCollectionTestApp(t)

	body, _ := json.Marshal(map[string]string{"name": "Want to Watch", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)
}

func TestCollectionHandler_List(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create one
	body, _ := json.Marshal(map[string]string{"name": "Horror", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	_, err := app.Test(req)
	require.NoError(t, err)

	// List
	req = httptest.NewRequest("GET", "/api/collections", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var cols []models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &cols)
	assert.Len(t, cols, 1)
}

func TestCollectionHandler_Update(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create
	body, _ := json.Marshal(map[string]string{"name": "Old Name", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Update
	body, _ = json.Marshal(map[string]string{"name": "New Name"})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(col.ID)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestCollectionHandler_Delete(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create
	body, _ := json.Marshal(map[string]string{"name": "ToDelete", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Delete
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(col.ID)), nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestCollectionHandler_UpdateType(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create
	body, _ := json.Marshal(map[string]string{"name": "Old Name", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Update type → audio применяется.
	body, _ = json.Marshal(map[string]string{"type": string(models.MediaTypeAudio)})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(col.ID)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	buf.Reset()
	buf.ReadFrom(resp.Body)
	var updated models.Collection
	require.NoError(t, json.Unmarshal(buf.Bytes(), &updated))
	assert.Equal(t, models.MediaTypeAudio, updated.Type)
}

func TestCollectionHandler_UpdateInvalidType(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create
	body, _ := json.Marshal(map[string]string{"name": "Old Name", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Невалидный type → 400.
	body, _ = json.Marshal(map[string]string{"type": "garbage"})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(col.ID)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestCollectionHandler_AddItemDuplicate(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create collection
	body, _ := json.Marshal(map[string]string{"name": "My List", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Add item — первый раз 201.
	body, _ = json.Marshal(map[string]uint{"media_id": 1})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	// Дубликат — 409.
	body, _ = json.Marshal(map[string]uint{"media_id": 1})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestCollectionHandler_AddAndRemoveItem(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create collection
	body, _ := json.Marshal(map[string]string{"name": "My List", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// Add item
	body, _ = json.Marshal(map[string]uint{"media_id": 1})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	// List items
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Remove item
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items/1", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestCollectionHandler_AddItemConcurrent(t *testing.T) {
	app := setupCollectionTestApp(t)

	// Create collection
	body, _ := json.Marshal(map[string]string{"name": "My List", "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)

	var col models.Collection
	buf := bytes.Buffer{}
	buf.ReadFrom(resp.Body)
	json.Unmarshal(buf.Bytes(), &col)

	// 30 параллельных добавлений трёх медиа: каждый медиа должен
	// добавиться ровно один раз (201), остальные — 409, но НЕ 500
	// (позиция и дубликат обрабатываются атомарно).
	const requests = 30
	statuses := make(chan int, requests)
	for i := 0; i < requests; i++ {
		go func(mediaID uint) {
			b, _ := json.Marshal(map[string]uint{"media_id": mediaID})
			req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(col.ID))+"/items", bytes.NewReader(b))
			req.Header.Set("Content-Type", "application/json")
			resp, err := app.Test(req)
			require.NoError(t, err)
			statuses <- resp.StatusCode
		}(uint(i%3 + 1))
	}

	created, conflicts, serverErrors := 0, 0, 0
	for i := 0; i < requests; i++ {
		switch <-statuses {
		case fiber.StatusCreated:
			created++
		case fiber.StatusConflict:
			conflicts++
		default:
			serverErrors++
		}
	}
	assert.Equal(t, 3, created, "каждое медиа добавляется ровно один раз")
	assert.Equal(t, requests-3, conflicts)
	assert.Equal(t, 0, serverErrors, "конкурентные добавления не должны давать 500")
}
