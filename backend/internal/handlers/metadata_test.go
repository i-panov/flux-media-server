package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
)

func setupMetadataTestApp(t *testing.T) *fiber.App {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))

	handler := NewMetadataHandler(mediaRepo)
	app := fiber.New()

	app.Get("/api/metadata/search", handler.Search)
	app.Put("/api/metadata/:mediaId", handler.Update)
	app.Post("/api/metadata/:mediaId/refresh", handler.Refresh)

	return app
}

func TestMetadataHandler_SearchQueryTooLong(t *testing.T) {
	app := setupMetadataTestApp(t)

	query := strings.Repeat("a", 257)
	resp, err := app.Test(httptest.NewRequest("GET", "/api/metadata/search?q="+query, nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

// Лимит считается по символам, а не байтам: 257 кириллических символов —
// это 514 байт, но визуально строка длиннее лимита и должна отклоняться,
// а 256 — проходить (при байтовом подсчёте ложно отклонялась бы вдвое
// короче).
func TestMetadataHandler_SearchLimitByRunes(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/metadata/search?q="+strings.Repeat("ф", 257), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/metadata/search?q="+strings.Repeat("ф", 256), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestMetadataHandler_SearchValid(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/metadata/search?q=Interstellar.2014.mkv", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestMetadataHandler_UpdateInvalidYear(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]int{"year": 1500})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMetadataHandler_UpdateFutureYearTooFar(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]int{"year": 9999})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestMetadataHandler_UpdateInvalidRating(t *testing.T) {
	app := setupMetadataTestApp(t)

	for _, rating := range []float64{-1, 11, 10.5} {
		body, _ := json.Marshal(map[string]float64{"rating": rating})
		req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "rating %v must be rejected", rating)
	}
}

func TestMetadataHandler_UpdateValid(t *testing.T) {
	app := setupMetadataTestApp(t)

	body, _ := json.Marshal(map[string]interface{}{"year": 2001, "rating": 8.5})
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func putMetadata(t *testing.T, app *fiber.App, body map[string]interface{}) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	return resp
}

func decodeMedia(t *testing.T, resp *http.Response) map[string]interface{} {
	t.Helper()
	defer resp.Body.Close()
	var decoded map[string]interface{}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&decoded))
	return decoded
}

func TestMetadataHandler_UpdateSourceURLValid(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp := putMetadata(t, app, map[string]interface{}{
		"source_url": "  https://www.youtube.com/watch?v=abc123  ",
	})
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(
		t,
		"https://www.youtube.com/watch?v=abc123",
		decodeMedia(t, resp)["source_url"],
	)
}

func TestMetadataHandler_UpdateSourceURLInvalid(t *testing.T) {
	for _, raw := range []string{
		"not a url",
		"ftp://example.com/x",
		"javascript:alert(1)",
		"https://",
		strings.Repeat("a", 2049),
	} {
		app := setupMetadataTestApp(t)

		resp := putMetadata(t, app, map[string]interface{}{"source_url": raw})
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "raw %q", raw)
		resp.Body.Close()
	}
}

func TestMetadataHandler_UpdateSourceURLClear(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp := putMetadata(t, app, map[string]interface{}{
		"source_url": "https://youtu.be/abc123",
	})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	resp.Body.Close()

	// Пустая строка стирает ссылку, а не игнорируется.
	resp = putMetadata(t, app, map[string]interface{}{"source_url": "   "})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "", decodeMedia(t, resp)["source_url"])
}

func TestMetadataHandler_UpdateSourceURLNotProvided(t *testing.T) {
	app := setupMetadataTestApp(t)

	// Без ключа в теле существующая ссылка не трогается.
	putResp := putMetadata(t, app, map[string]interface{}{
		"source_url": "https://youtu.be/abc123",
	})
	require.Equal(t, fiber.StatusOK, putResp.StatusCode)
	putResp.Body.Close()

	resp := putMetadata(t, app, map[string]interface{}{"title": "New Title"})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	decoded := decodeMedia(t, resp)
	assert.Equal(t, "https://youtu.be/abc123", decoded["source_url"])
	assert.Equal(t, "New Title", decoded["title"])
}

func TestMetadataHandler_UpdateSourceURLAtomic(t *testing.T) {
	app := setupMetadataTestApp(t)

	// Невалидная ссылка отклоняет весь запрос: валидный title из того же
	// тела применяться не должен.
	resp := putMetadata(t, app, map[string]interface{}{
		"title":      "New Title",
		"source_url": "bogus",
	})
	require.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	resp.Body.Close()

	resp = putMetadata(t, app, map[string]interface{}{
		"source_url": "https://youtu.be/abc123",
	})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	decoded := decodeMedia(t, resp)
	assert.Equal(t, "https://youtu.be/abc123", decoded["source_url"])
	// Title из отклонённого запроса не применился.
	assert.Equal(t, "Test Movie", decoded["title"])
}

func TestMetadataHandler_UpdateSourceURLNonString(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp := putMetadata(t, app, map[string]interface{}{"source_url": 123})
	require.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	resp.Body.Close()
}

func TestMetadataHandler_UpdateRequiresAdmin(t *testing.T) {

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	ctx := context.Background()
	userRepo := repository.NewUserRepository(db)
	// Первый пользователь становится админом автоматически.
	require.NoError(t, userRepo.Create(ctx, &models.User{Email: "admin@example.com"}))
	require.NoError(t, userRepo.Create(ctx, &models.User{Email: "user@example.com"}))

	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, mediaRepo.Create(ctx, &models.Media{
		Title:    "Test Movie",
		Type:     models.MediaTypeVideo,
		FilePath: "/test.mkv",
	}))

	handler := NewMetadataHandler(mediaRepo)
	app := fiber.New()
	// Стаб аутентификации вместо JWT: подкладывает user_id в Locals,
	// дальше работает настоящий RequireAdmin. Если middleware снимут
	// с роута в app.go, этот тест упадёт и напомнит вернуть.
	var authedUserID uint
	var authed bool
	app.Put("/api/metadata/:mediaId",
		func(c *fiber.Ctx) error {
			if authed {
				c.Locals(middleware.LocalsUserID, authedUserID)
			}
			return c.Next()
		},
		middleware.RequireAdmin(userRepo),
		handler.Update,
	)

	put := func(body map[string]interface{}) *http.Response {
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest("PUT", "/api/metadata/1", bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		return resp
	}

	// Без пользователя — 401.
	authed = false
	resp := put(map[string]interface{}{"source_url": "https://youtu.be/x"})
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	resp.Body.Close()

	// Не админ (второй пользователь) — 403.
	authed, authedUserID = true, 2
	resp = put(map[string]interface{}{"source_url": "https://youtu.be/x"})
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
	resp.Body.Close()

	// Админ (первый пользователь) — 200.
	authed, authedUserID = true, 1
	resp = put(map[string]interface{}{"source_url": "https://youtu.be/x"})
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "https://youtu.be/x", decodeMedia(t, resp)["source_url"])
}

func TestMetadataHandler_UpdateMissingMedia404(t *testing.T) {
	app := setupMetadataTestApp(t)

	put := func(id string, body map[string]interface{}) *http.Response {
		raw, _ := json.Marshal(body)
		req := httptest.NewRequest("PUT", "/api/metadata/"+id, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		resp, err := app.Test(req)
		require.NoError(t, err)
		return resp
	}

	// Несуществующий id — 404 и для обычных полей, и для ссылки.
	for _, body := range []map[string]interface{}{
		{"title": "Ghost"},
		{"source_url": "https://youtu.be/x"},
	} {
		resp := put("999", body)
		assert.Equal(t, fiber.StatusNotFound, resp.StatusCode, "body %v", body)
		resp.Body.Close()
	}
}

func TestMetadataHandler_UpdateSourceURLEdgeCases(t *testing.T) {
	// null в JSON = ключ не прислан = ссылку не трогать.
	app := setupMetadataTestApp(t)
	resp := putMetadata(t, app, map[string]interface{}{
		"source_url": "https://youtu.be/abc123",
	})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	resp.Body.Close()

	resp = putMetadata(t, app, map[string]interface{}{"source_url": nil})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "https://youtu.be/abc123", decodeMedia(t, resp)["source_url"])

	// userinfo и управляющие символы отклоняются через PUT.
	for _, raw := range []string{
		"http://user:pass@example.com/",
		"https://user@example.com/",
		"http://example.com/a\nb",
	} {
		r := putMetadata(t, app, map[string]interface{}{"source_url": raw})
		assert.Equal(t, fiber.StatusBadRequest, r.StatusCode, "raw %q", raw)
		r.Body.Close()
	}

	// Граница длины через PUT: ровно 2048 проходит, 2049 — нет.
	base := "https://example.com/"
	okRaw := base + strings.Repeat("a", 2048-len(base))
	resp = putMetadata(t, app, map[string]interface{}{"source_url": okRaw})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, okRaw, decodeMedia(t, resp)["source_url"])

	resp = putMetadata(t, app, map[string]interface{}{
		"source_url": base + strings.Repeat("a", 2049-len(base)),
	})
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Contains(t, readBody(t, resp), "too long")
	resp.Body.Close()
}

func TestMetadataHandler_UpdateErrorTexts(t *testing.T) {
	app := setupMetadataTestApp(t)

	resp := putMetadata(t, app, map[string]interface{}{"source_url": "bogus"})
	require.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Contains(t, readBody(t, resp), "must be an http(s) URL")
	resp.Body.Close()
}

func TestMetadataHandler_UpdateRefreshesUpdatedAt(t *testing.T) {
	app := setupMetadataTestApp(t)
	before := time.Now().Add(-time.Minute)

	resp := putMetadata(t, app, map[string]interface{}{
		"source_url": "https://youtu.be/abc123",
	})
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	decoded := decodeMedia(t, resp)

	updatedAt, ok := decoded["updated_at"].(string)
	require.True(t, ok, "response must carry updated_at")
	parsed, err := time.Parse(time.RFC3339, updatedAt)
	require.NoError(t, err)
	assert.True(t, !parsed.Before(before), "updated_at must be fresh, got %v", parsed)
}

func readBody(t *testing.T, resp *http.Response) string {
	t.Helper()
	defer resp.Body.Close()
	buf := new(bytes.Buffer)
	_, err := buf.ReadFrom(resp.Body)
	require.NoError(t, err)
	return buf.String()
}
