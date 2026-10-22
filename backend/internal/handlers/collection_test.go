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
	"flux/internal/response"
)

func setupCollectionTestApp(t *testing.T) *fiber.App {
	userID := uint(1)
	return setupCollectionTestAppAs(t, &userID)
}

// setupCollectionTestAppAs — то же приложение, но user_id берётся из
// указателя: проверки владения коллекцией нуждаются во втором
// пользователе (иначе 403 не проверить).
func setupCollectionTestAppAs(t *testing.T, userID *uint) *fiber.App {
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
		c.Locals("user_id", *userID)
		return c.Next()
	})

	app.Post("/api/collections", handler.Create)
	app.Get("/api/collections", handler.List)
	app.Put("/api/collections/:id", handler.Update)
	app.Delete("/api/collections/:id", handler.Delete)
	app.Post("/api/collections/:id/items", handler.AddItem)
	app.Post("/api/collections/:id/items/move", handler.MoveItem)
	app.Post("/api/collections/:id/items/bulk", handler.AddItemsBulk)
	app.Post("/api/collections/:id/items/move/bulk", handler.MoveItemsBulk)
	app.Delete("/api/collections/:id/items", handler.RemoveItemsBulk)
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

// createCollectionForBulk создаёт коллекцию и возвращает её id.
func createCollectionForBulk(t *testing.T, app *fiber.App, name string) uint {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusCreated, resp.StatusCode)

	var col models.Collection
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &col))
	return col.ID
}

func TestCollectionHandler_AddItemsBulk(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	// Три файла сезона + несуществующий id: запрос не должен падать.
	body, _ := json.Marshal(map[string][]uint{"media_ids": {1, 2, 3, 999}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var result BulkItemsResult
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &result))
	assert.ElementsMatch(t, []uint{1, 2, 3}, result.Added)
	assert.Equal(t, []uint{999}, result.Skipped)

	// Повторное добавление тех же файлов — пропуск, а не 409 на весь запрос.
	body, _ = json.Marshal(map[string][]uint{"media_ids": {1, 2}})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	buf.Reset()
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &result))
	assert.Empty(t, result.Added)
	assert.ElementsMatch(t, []uint{1, 2}, result.Skipped)
}

func TestCollectionHandler_AddItemsBulkEmptyList(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	body, _ := json.Marshal(map[string][]uint{"media_ids": {}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestCollectionHandler_MoveItemsBulk(t *testing.T) {
	app := setupCollectionTestApp(t)
	sourceID := createCollectionForBulk(t, app, "Season 1")
	targetID := createCollectionForBulk(t, app, "Season 2")

	// Наполняем источник.
	body, _ := json.Marshal(map[string][]uint{"media_ids": {1, 2, 3}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(sourceID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Переносим пачкой. Медиа 4 в источнике нет — пропуск.
	body, _ = json.Marshal(map[string]any{"media_ids": []uint{1, 2, 4}, "to_collection_id": targetID})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(sourceID))+"/items/move/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var result BulkItemsResult
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &result))
	assert.ElementsMatch(t, []uint{1, 2}, result.Moved)
	assert.Equal(t, []uint{4}, result.Skipped)

	// В источнике осталось одно, в цели — два.
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(sourceID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	buf.Reset()
	_, _ = buf.ReadFrom(resp.Body)
	var sourceItems []models.Media
	require.NoError(t, json.Unmarshal(buf.Bytes(), &sourceItems))
	assert.Len(t, sourceItems, 1)

	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(targetID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	buf.Reset()
	_, _ = buf.ReadFrom(resp.Body)
	var targetItems []models.Media
	require.NoError(t, json.Unmarshal(buf.Bytes(), &targetItems))
	assert.Len(t, targetItems, 2)
}

func TestCollectionHandler_RemoveItemsBulk(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	body, _ := json.Marshal(map[string][]uint{"media_ids": {1, 2}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	body, _ = json.Marshal(map[string][]uint{"media_ids": {1, 2}})
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(colID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var result BulkItemsResult
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &result))
	assert.ElementsMatch(t, []uint{1, 2}, result.Removed)

	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(colID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	buf.Reset()
	_, _ = buf.ReadFrom(resp.Body)
	var items []models.Media
	require.NoError(t, json.Unmarshal(buf.Bytes(), &items))
	assert.Empty(t, items)
}

// Регрессия (безопасность): getOwnedCollection писал 401/403/404 и
// возвращал nil-ошибку (response.Error отдаёт nil при успешной записи
// ответа), поэтому проверка `err != nil` не срабатывала и обработчик
// продолжал работать с чужой коллекцией: клиент получал 403, а данные
// менялись.
func TestCollectionHandler_ForeignCollectionNotModified(t *testing.T) {
	userID := uint(1)
	app := setupCollectionTestAppAs(t, &userID)
	colID := createCollectionForBulk(t, app, "Чужая")

	// Запрос от другого пользователя.
	userID = 2
	body, _ := json.Marshal(map[string][]uint{"media_ids": {1, 2}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	// Возвращаемся владельцем и смотрим содержимое: оно должно быть пустым.
	userID = 1
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(colID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	var items []models.Media
	require.NoError(t, json.Unmarshal(buf.Bytes(), &items))
	assert.Empty(t, items, "в чужую коллекцию не должно попасть ни одного элемента")
}

// Тот же сценарий для одиночного добавления: уязвимость была не только
// в новых bulk-хендлерах.
func TestCollectionHandler_ForeignCollectionSingleAddNotModified(t *testing.T) {
	userID := uint(1)
	app := setupCollectionTestAppAs(t, &userID)
	colID := createCollectionForBulk(t, app, "Чужая")

	userID = 2
	body, _ := json.Marshal(map[string]uint{"media_id": 1})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	userID = 1
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(colID))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	var items []models.Media
	require.NoError(t, json.Unmarshal(buf.Bytes(), &items))
	assert.Empty(t, items)
}

// Несуществующая коллекция: 404 и никакой паники. Раньше source/target
// были nil, и обращение к source.Type давало 500.
func TestCollectionHandler_MissingCollection(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	body, _ := json.Marshal(map[string][]uint{"media_ids": {1}})
	req := httptest.NewRequest("POST", "/api/collections/999/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	// Групповой перенос с несуществующей целью — тоже 404, не 500.
	body, _ = json.Marshal(map[string]any{"media_ids": []uint{1}, "to_collection_id": 999})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/move/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

// Тело ошибки 400 не должно затираться результатом операции.
func TestCollectionHandler_AddItemsBulkKeepsErrorBody(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	body, _ := json.Marshal(map[string][]uint{"media_ids": {}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	var errResp response.ErrorResponse
	require.NoError(t, json.Unmarshal(buf.Bytes(), &errResp))
	assert.Equal(t, "media_ids is required", errResp.Error)
}

// Элемента в коллекции нет — «пропущено», а не «удалено».
func TestCollectionHandler_RemoveItemsBulkSkipsMissing(t *testing.T) {
	app := setupCollectionTestApp(t)
	colID := createCollectionForBulk(t, app, "Season 1")

	body, _ := json.Marshal(map[string][]uint{"media_ids": {1}})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items/bulk", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Удаляем первый (он есть) и второй (которого в коллекции нет).
	body, _ = json.Marshal(map[string][]uint{"media_ids": {1, 2}})
	req = httptest.NewRequest("DELETE", "/api/collections/"+strconv.Itoa(int(colID))+"/items", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var result BulkItemsResult
	buf := bytes.Buffer{}
	_, _ = buf.ReadFrom(resp.Body)
	require.NoError(t, json.Unmarshal(buf.Bytes(), &result))
	assert.Equal(t, []uint{1}, result.Removed)
	assert.Equal(t, []uint{2}, result.Skipped)
}
