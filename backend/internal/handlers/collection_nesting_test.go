package handlers

import (
	"bytes"
	"encoding/json"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

func TestCollectionHandler_CreateWithParent(t *testing.T) {
	app := setupCollectionTestApp(t)

	mkCol := func(name string) uint {
		body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	root := mkCol("Сериал")

	// Успех: 201 сразу с parent_id.
	body, _ := json.Marshal(map[string]any{"name": "S01", "type": "video", "parent_id": root})
	req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 201, resp.StatusCode)
	var created models.Collection
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&created))
	require.NotNil(t, created.ParentID)
	assert.Equal(t, root, *created.ParentID)

	// Призрак-родитель: 404 и никакой сироты в списке.
	body, _ = json.Marshal(map[string]any{"name": "Сирота", "type": "video", "parent_id": 9999})
	req = httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 404, resp.StatusCode)

	req = httptest.NewRequest("GET", "/api/collections", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	var cols []models.Collection
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&cols))
	for _, c := range cols {
		assert.NotEqual(t, "Сирота", c.Name, "отказанная коллекция не осталась корнем")
	}
}

func TestCollectionHandler_MoveItem_Errors(t *testing.T) {
	app := setupCollectionTestApp(t)

	mkCol := func(name string) uint {
		body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	source := mkCol("A")
	target := mkCol("B")

	move := func(src, dst, media uint) int {
		body, _ := json.Marshal(map[string]uint{"media_id": media, "to_collection_id": dst})
		req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(src))+"/items/move", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		return resp.StatusCode
	}

	// Не член source (медиа 2 существует, но лежит не в A): 404.
	assert.Equal(t, 404, move(source, target, 2))
	// В себя: 400.
	assert.Equal(t, 400, move(source, source, 1))
	// Несуществующее медиа: 404.
	assert.Equal(t, 404, move(source, target, 9999))
}

func TestCollectionHandler_MoveItem(t *testing.T) {
	app := setupCollectionTestApp(t)

	mkCol := func(name string) uint {
		body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	source := mkCol("A")
	target := mkCol("B")

	addItem := func(colID, mediaID uint) {
		body, _ := json.Marshal(map[string]uint{"media_id": mediaID})
		req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
	}
	addItem(source, 1)

	// Перенос 1 из A в B.
	body, _ := json.Marshal(map[string]uint{"media_id": 1, "to_collection_id": target})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(source))+"/items/move", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// В источнике пусто, в целевой — элемент.
	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(source))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	var srcItems []models.Media
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&srcItems))
	assert.Empty(t, srcItems)

	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(target))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	var dstItems []models.Media
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&dstItems))
	require.Len(t, dstItems, 1)
	assert.Equal(t, uint(1), dstItems[0].ID)

	// Повторный перенос того же (уже нет в A): 404 на медиа? Нет —
	// медиа существует, но записи в source нет: MoveItemAtomic вставит
	// в target дубль → 409. Проверяем конфликт без потери.
	addItem(source, 2)
	body, _ = json.Marshal(map[string]uint{"media_id": 2, "to_collection_id": target})
	req = httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(source))+"/items/move", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
}

func TestCollectionHandler_MoveItem_ConflictKeepsSource(t *testing.T) {
	app := setupCollectionTestApp(t)

	mkCol := func(name string) uint {
		body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	source := mkCol("A")
	target := mkCol("B")

	add := func(colID, mediaID uint) {
		body, _ := json.Marshal(map[string]uint{"media_id": mediaID})
		req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(colID))+"/items", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
	}
	add(source, 1)
	add(target, 1)

	// Медиа уже в целевой: 409, исходник цел.
	body, _ := json.Marshal(map[string]uint{"media_id": 1, "to_collection_id": target})
	req := httptest.NewRequest("POST", "/api/collections/"+strconv.Itoa(int(source))+"/items/move", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 409, resp.StatusCode)

	req = httptest.NewRequest("GET", "/api/collections/"+strconv.Itoa(int(source))+"/items", nil)
	resp, err = app.Test(req)
	require.NoError(t, err)
	var srcItems []models.Media
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&srcItems))
	assert.Len(t, srcItems, 1)
}

func TestCollectionHandler_UpdateParent(t *testing.T) {
	app := setupCollectionTestApp(t)

	mkCol := func(name string) uint {
		body, _ := json.Marshal(map[string]string{"name": name, "type": string(models.MediaTypeVideo)})
		req := httptest.NewRequest("POST", "/api/collections", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		require.Equal(t, 201, resp.StatusCode)
		var col models.Collection
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&col))
		return col.ID
	}
	root := mkCol("Сериал")
	season := mkCol("Season 01")

	// PUT с parent_id переносит под родителя.
	body, _ := json.Marshal(map[string]any{"parent_id": root})
	req := httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(season)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)

	// PUT без parent_id переименовывает, но не сбрасывает родителя.
	body, _ = json.Marshal(map[string]any{"name": "Season 1"})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(season)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	var updated models.Collection
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&updated))
	require.NotNil(t, updated.ParentID)
	assert.Equal(t, root, *updated.ParentID)

	// Цикл: корень под потомка — 400.
	body, _ = json.Marshal(map[string]any{"parent_id": season})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(root)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 400, resp.StatusCode)

	// Явный null — возврат в корень.
	body, _ = json.Marshal(map[string]any{"parent_id": nil})
	req = httptest.NewRequest("PUT", "/api/collections/"+strconv.Itoa(int(season)), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, 200, resp.StatusCode)
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&updated))
	assert.Nil(t, updated.ParentID)
}
