package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

// testArtistHandler создаёт хендлер с файловой БД и временным каталогом
// обложек.
func testArtistHandler(t *testing.T) (*fiber.App, *ArtistHandler, string) {
	t.Helper()
	db, err := repository.InitDB(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	repo := repository.NewArtistRepository(db)
	_, err = repo.FindOrCreateByName(context.Background(), "Artist A")
	require.NoError(t, err)
	_, err = repo.FindOrCreateByName(context.Background(), "Artist B")
	require.NoError(t, err)

	coverDir := t.TempDir()
	h := NewArtistHandler(repo, coverDir)

	app := fiber.New()
	app.Put("/artists/:id", h.Update)
	app.Post("/artists/:id/cover", h.UploadCover)
	app.Get("/artists/:id/cover", h.GetCover)
	app.Get("/artists", h.List)
	return app, h, coverDir
}

// parseResp разбирает JSON-ответ теста.
func parseResp(t *testing.T, resp *http.Response, v interface{}) {
	t.Helper()
	require.NoError(t, json.NewDecoder(resp.Body).Decode(v))
}

func TestArtistUpdate(t *testing.T) {
	app, _, _ := testArtistHandler(t)

	t.Run("renames artist", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPut, "/artists/1", bytes.NewBufferString(`{"name":"New Name"}`))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var artist models.Artist
		parseResp(t, resp, &artist)
		assert.Equal(t, "New Name", artist.Name)
	})

	t.Run("rejects empty name", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPut, "/artists/1", bytes.NewBufferString(`{"name":"  "}`))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	t.Run("conflicts with existing name", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPut, "/artists/1", bytes.NewBufferString(`{"name":"Artist B"}`))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, http.StatusConflict, resp.StatusCode)
	})

	t.Run("404 for missing artist", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPut, "/artists/999", bytes.NewBufferString(`{"name":"X"}`))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, http.StatusNotFound, resp.StatusCode)
	})
}

func TestArtistCover(t *testing.T) {
	app, _, coverDir := testArtistHandler(t)

	// 404 до загрузки.
	resp, err := app.Test(httptest.NewRequest(http.MethodGet, "/artists/1/cover", nil))
	require.NoError(t, err)
	assert.Equal(t, http.StatusNotFound, resp.StatusCode)

	// Загрузка PNG-обложки.
	var body bytes.Buffer
	w := multipart.NewWriter(&body)
	fw, err := w.CreateFormFile("cover", "cover.png")
	require.NoError(t, err)
	// Минимальный валидный PNG-заголовок.
	_, err = fw.Write([]byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4})
	require.NoError(t, err)
	require.NoError(t, w.Close())

	req := httptest.NewRequest(http.MethodPost, "/artists/1/cover", &body)
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, http.StatusOK, resp.StatusCode)

	// Файл лежит на диске.
	files, err := filepath.Glob(filepath.Join(coverDir, "artist_1.*"))
	require.NoError(t, err)
	require.Len(t, files, 1)
	assert.Equal(t, ".png", filepath.Ext(files[0]))

	// GET отдаёт файл с правильным MIME.
	resp, err = app.Test(httptest.NewRequest(http.MethodGet, "/artists/1/cover", nil))
	require.NoError(t, err)
	assert.Equal(t, http.StatusOK, resp.StatusCode)
	assert.Equal(t, "image/png", resp.Header.Get("Content-Type"))
	got, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, 12, len(got))

	// Замена на jpg удаляет старый png.
	var body2 bytes.Buffer
	w2 := multipart.NewWriter(&body2)
	fw2, err := w2.CreateFormFile("cover", "cover.jpg")
	require.NoError(t, err)
	_, err = fw2.Write([]byte{0xFF, 0xD8, 0xFF, 0xE0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11})
	require.NoError(t, err)
	require.NoError(t, w2.Close())
	req2 := httptest.NewRequest(http.MethodPost, "/artists/1/cover", &body2)
	req2.Header.Set("Content-Type", w2.FormDataContentType())
	resp, err = app.Test(req2)
	require.NoError(t, err)
	assert.Equal(t, http.StatusOK, resp.StatusCode)

	files, err = filepath.Glob(filepath.Join(coverDir, "artist_1.*"))
	require.NoError(t, err)
	require.Len(t, files, 1)
	assert.Equal(t, ".jpg", filepath.Ext(files[0]))
	resp, err = app.Test(httptest.NewRequest(http.MethodGet, "/artists/1/cover", nil))
	require.NoError(t, err)
	assert.Equal(t, "image/jpeg", resp.Header.Get("Content-Type"))

	// Неподдерживаемый формат — 400.
	var body3 bytes.Buffer
	w3 := multipart.NewWriter(&body3)
	fw3, err := w3.CreateFormFile("cover", "cover.gif")
	require.NoError(t, err)
	_, err = fw3.Write([]byte("GIF89a"))
	require.NoError(t, err)
	require.NoError(t, w3.Close())
	req3 := httptest.NewRequest(http.MethodPost, "/artists/1/cover", &body3)
	req3.Header.Set("Content-Type", w3.FormDataContentType())
	resp, err = app.Test(req3)
	require.NoError(t, err)
	assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
}

func TestArtistListHasCover(t *testing.T) {
	app, _, coverDir := testArtistHandler(t)

	// У артиста 1 — обложка, у 2 — нет.
	require.NoError(t, os.WriteFile(filepath.Join(coverDir, "artist_1.jpg"), []byte{0xFF, 0xD8, 0xFF}, 0644))

	resp, err := app.Test(httptest.NewRequest(http.MethodGet, "/artists", nil))
	require.NoError(t, err)
	assert.Equal(t, http.StatusOK, resp.StatusCode)

	var body struct {
		Items []models.Artist `json:"items"`
	}
	parseResp(t, resp, &body)
	require.Len(t, body.Items, 2)
	assert.True(t, body.Items[0].HasCover || body.Items[1].HasCover)
	for _, a := range body.Items {
		if a.Name == "Artist A" {
			assert.True(t, a.HasCover)
		} else {
			assert.False(t, a.HasCover)
		}
	}
}
