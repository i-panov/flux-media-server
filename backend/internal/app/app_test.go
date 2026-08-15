package app

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/response"
	"flux/internal/services"
)

func newTestApp(t *testing.T) *App {
	t.Helper()
	cfg := &config.Config{
		Server:   config.ServerConfig{Port: 0, Debug: true, MaxUploadSize: 100 << 20},
		Database: config.DatabaseConfig{Path: ":memory:"},
		Auth: config.AuthConfig{
			JWTSecret:         "test-secret-that-is-at-least-32-characters-long",
			JWTExpiry:         24,
			CodeLength:        6,
			CodeExpiry:        300,
			MaxOTPEntries:     1000,
			AllowUnknownEmail: true,
		},
		Media: config.MediaConfig{VideoPath: t.TempDir() + "/video", AudioPath: t.TempDir() + "/audio"},
	}
	application, err := New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown(context.Background()) })
	return application
}

func jsonBody(t *testing.T, v interface{}) io.Reader {
	t.Helper()
	b, err := json.Marshal(v)
	require.NoError(t, err)
	return bytes.NewReader(b)
}

func parseResp(t *testing.T, resp *http.Response, v interface{}) {
	t.Helper()
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	if v != nil {
		require.NoError(t, json.Unmarshal(body, v), "body: %s", string(body))
	}
}

func testReq(method, uri string, body io.Reader) *http.Request {
	req := httptest.NewRequest(method, uri, body)
	req.Header.Set("Content-Type", "application/json")
	return req
}

func getAuthToken(t *testing.T, application *App, email string) string {
	t.Helper()
	code, err := application.OTPStore.Generate(email)
	require.NoError(t, err)

	b, _ := json.Marshal(map[string]string{"email": email, "code": code})
	req := testReq("POST", "/api/auth/verify-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseResp(t, resp, &body)
	return body["token"].(string)
}

func authReq(method, uri, token string) *http.Request {
	req := testReq(method, uri, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	return req
}

// --- Health check ---

func TestHealthEndpoint(t *testing.T) {
	application := newTestApp(t)

	resp, err := application.Fiber.Test(httptest.NewRequest("GET", "/api/health", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]string
	parseResp(t, resp, &body)
	assert.Equal(t, "ok", body["status"])
}

func TestLegacyHealthEndpointGone(t *testing.T) {
	application := newTestApp(t)

	resp, err := application.Fiber.Test(httptest.NewRequest("GET", "/health", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

// --- Security headers ---

func TestSecurityHeaders(t *testing.T) {
	application := newTestApp(t)

	resp, err := application.Fiber.Test(httptest.NewRequest("GET", "/api/health", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "nosniff", resp.Header.Get("X-Content-Type-Options"))
	assert.Equal(t, "DENY", resp.Header.Get("X-Frame-Options"))
	assert.Equal(t, "no-referrer", resp.Header.Get("Referrer-Policy"))
}

// --- Auth flow ---

func TestAuthRequestCode(t *testing.T) {
	application := newTestApp(t)

	b, _ := json.Marshal(map[string]string{"email": "test@example.com"})
	req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseResp(t, resp, &body)
	assert.Equal(t, "Code sent successfully", body["message"])
}

func TestAuthRequestCodeUnknownEmail(t *testing.T) {
	cfg := &config.Config{
		Database: config.DatabaseConfig{Path: ":memory:"},
		Auth: config.AuthConfig{
			JWTSecret:         "test-secret-that-is-at-least-32-characters-long",
			CodeLength:        6,
			CodeExpiry:        300,
			MaxOTPEntries:     1000,
			AllowedEmails:     []string{"admin@example.com"},
			AllowUnknownEmail: false,
		},
		Media: config.MediaConfig{VideoPath: t.TempDir() + "/video", AudioPath: t.TempDir() + "/audio"},
	}
	application, err := New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown(context.Background()) })

	b, _ := json.Marshal(map[string]string{"email": "unknown@example.com"})
	req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Не раскрываем существование email в allowlist — ответ как при успехе.
	var body map[string]interface{}
	parseResp(t, resp, &body)
	assert.Equal(t, "Code sent successfully", body["message"])
}

func TestAuthVerifyCode(t *testing.T) {
	application := newTestApp(t)

	code, err := application.OTPStore.Generate("test@example.com")
	require.NoError(t, err)

	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": code})
	req := testReq("POST", "/api/auth/verify-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseResp(t, resp, &body)
	assert.NotEmpty(t, body["token"])

	user, ok := body["user"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "test@example.com", user["email"])
}

func TestAuthVerifyCodeInvalid(t *testing.T) {
	application := newTestApp(t)

	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": "000000"})
	req := testReq("POST", "/api/auth/verify-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)

	var body response.ErrorResponse
	parseResp(t, resp, &body)
	assert.Equal(t, "Invalid or expired code", body.Error)
}

// --- Protected routes ---

func TestProtectedRouteNoToken(t *testing.T) {
	application := newTestApp(t)

	req := httptest.NewRequest("GET", "/api/auth/me", nil)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestProtectedRouteInvalidToken(t *testing.T) {
	application := newTestApp(t)

	req := httptest.NewRequest("GET", "/api/auth/me", nil)
	req.Header.Set("Authorization", "Bearer invalid-token")
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestAuthMe(t *testing.T) {
	application := newTestApp(t)
	token := getAuthToken(t, application, "me@example.com")

	resp, err := application.Fiber.Test(authReq("GET", "/api/auth/me", token))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseResp(t, resp, &body)
	assert.Equal(t, "me@example.com", body["email"])
}

// --- Media ---

func TestMediaListEmpty(t *testing.T) {
	application := newTestApp(t)
	token := getAuthToken(t, application, "user@example.com")

	resp, err := application.Fiber.Test(authReq("GET", "/api/media", token))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseResp(t, resp, &body)
	assert.Equal(t, float64(0), body["total"])
}

// --- Body-size middleware ---

func TestBodySizeLimitRejectsLargeBodies(t *testing.T) {
	application := newTestApp(t)

	// 5 MB > maxAPIBodySize (4 MB) — fasthttp отклоняет тело на этапе
	// чтения (per-route лимит из HeaderReceived) и пишет 413 клиенту;
	// Fiber.Test в этом случае возвращает ошибку вместо ответа.
	body := bytes.NewReader(make([]byte, 5<<20))
	req := testReq("POST", "/api/auth/request-code", body)
	_, err := application.Fiber.Test(req)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "body size exceeds")
}

func TestBodySizeLimitAllowsNormalBodies(t *testing.T) {
	application := newTestApp(t)

	b, _ := json.Marshal(map[string]string{"email": "small@example.com"})
	req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestBodySizeLimitUploadRouteExempt(t *testing.T) {
	application := newTestApp(t)

	// Большое тело на upload-роуте пропускается body-size middleware и
	// отклоняется дальше AuthMiddleware (401), а не 413.
	body := bytes.NewReader(make([]byte, 5<<20))
	req := testReq("POST", "/api/media/upload", body)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestBodySizeLimitCoverRouteExempt(t *testing.T) {
	application := newTestApp(t)

	// Большое тело на cover-роуте также пропускается middleware.
	body := bytes.NewReader(make([]byte, 5<<20))
	req := testReq("PUT", "/api/media/1/cover", body)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

// Per-route лимиты через HeaderReceived: upload-роут принимает тела
// больше глобального fallback (25 МБ), не-upload роуты ограничены 4 МБ
// на уровне fasthttp (до обработчиков).
func TestHeaderReceivedPerRouteBodyLimits(t *testing.T) {
	application := newTestApp(t) // MaxUploadSize: 100 MB

	// 26 MB > globalBodyLimit (25 MB): upload-роут должен пропустить
	// (лимит MaxUploadSize), не-upload — быть отклонён на чтении.
	body := bytes.NewReader(make([]byte, 26<<20))

	req := testReq("POST", "/api/media/upload", body)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode,
		"upload route must accept bodies above the global fallback limit")

	body = bytes.NewReader(make([]byte, 26<<20))
	req = testReq("POST", "/api/auth/request-code", body)
	_, err = application.Fiber.Test(req)
	require.Error(t, err, "non-upload route must reject bodies above maxAPIBodySize")
	assert.Contains(t, err.Error(), "body size exceeds")
}

func TestIsUploadPath(t *testing.T) {
	for _, tc := range []struct {
		method, path string
		want         bool
	}{
		{fiber.MethodPost, "/api/media/upload", true},
		{fiber.MethodPost, "/api/media/upload/", false},
		{fiber.MethodPut, "/api/media/1/cover", true},
		{fiber.MethodPut, "/api/media/cover", true},
		{fiber.MethodGet, "/api/media/upload", false},
		{fiber.MethodPost, "/api/media/1/cover", false},
		{fiber.MethodPut, "/api/media/1/thumbnail", false},
		{fiber.MethodPost, "/api/auth/request-code", false},
	} {
		assert.Equal(t, tc.want, isUploadPath(tc.method, tc.path), "%s %s", tc.method, tc.path)
	}
}

// --- Metadata admin protection ---

func TestMetadataRoutesRequireAdmin(t *testing.T) {
	application := newTestApp(t)
	// Первый зарегистрированный пользователь становится админом — создаём
	// его заранее, чтобы regular@example.com точно не был админом.
	getAuthToken(t, application, "admin@example.com")
	token := getAuthToken(t, application, "regular@example.com")

	for _, tc := range []struct {
		method string
		uri    string
	}{
		{"POST", "/api/metadata/1/refresh"},
		{"PUT", "/api/metadata/1"},
	} {
		resp, err := application.Fiber.Test(authReq(tc.method, tc.uri, token))
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusForbidden, resp.StatusCode, "%s %s", tc.method, tc.uri)
	}
}

// --- OTPStore limits ---

func TestOTPStoreFull(t *testing.T) {
	cfg := &config.Config{
		Database: config.DatabaseConfig{Path: ":memory:"},
		Auth: config.AuthConfig{
			JWTSecret:     "test-secret-that-is-at-least-32-characters-long",
			CodeLength:    6,
			CodeExpiry:    300,
			MaxOTPEntries: 2,
		},
		Media: config.MediaConfig{VideoPath: t.TempDir() + "/video", AudioPath: t.TempDir() + "/audio"},
	}
	application, err := New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown(context.Background()) })

	_, err = application.OTPStore.Generate("a@test.com")
	require.NoError(t, err)
	_, err = application.OTPStore.Generate("b@test.com")
	require.NoError(t, err)

	_, err = application.OTPStore.Generate("c@test.com")
	assert.ErrorIs(t, err, services.ErrOTPStoreFull)
}

// --- Rate limiter ---

func TestAuthRateLimiter(t *testing.T) {
	cfg := &config.Config{
		Server:   config.ServerConfig{Port: 0, Debug: true},
		Database: config.DatabaseConfig{Path: ":memory:"},
		Auth: config.AuthConfig{
			JWTSecret:         "test-secret-that-is-at-least-32-characters-long",
			CodeLength:        6,
			CodeExpiry:        300,
			MaxOTPEntries:     1000,
			AllowUnknownEmail: true,
		},
		RateLimiter: config.RateLimiterConfig{Max: 3, Expiration: 60},
		Media:       config.MediaConfig{VideoPath: t.TempDir() + "/video", AudioPath: t.TempDir() + "/audio"},
	}
	application, err := New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown(context.Background()) })

	// Первые Max запросов проходят...
	for i := 0; i < 3; i++ {
		b, _ := json.Marshal(map[string]string{"email": "ratelimit@example.com"})
		req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))
		resp, err := application.Fiber.Test(req)
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode, "request %d should pass", i+1)
		resp.Body.Close()
	}

	// ...а следующий получает 429.
	b, _ := json.Marshal(map[string]string{"email": "ratelimit@example.com"})
	req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusTooManyRequests, resp.StatusCode)
}

func TestUploadRateLimiter(t *testing.T) {
	cfg := &config.Config{
		Server:   config.ServerConfig{Port: 0, Debug: true, MaxUploadSize: 100 << 20},
		Database: config.DatabaseConfig{Path: ":memory:"},
		Auth: config.AuthConfig{
			JWTSecret:         "test-secret-that-is-at-least-32-characters-long",
			JWTExpiry:         24,
			CodeLength:        6,
			CodeExpiry:        300,
			MaxOTPEntries:     1000,
			AllowUnknownEmail: true,
		},
		RateLimiter: config.RateLimiterConfig{Max: 2, Expiration: 60},
		Media:       config.MediaConfig{VideoPath: t.TempDir() + "/video", AudioPath: t.TempDir() + "/audio"},
	}
	application, err := New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown(context.Background()) })

	token := getAuthToken(t, application, "uploader@example.com")

	// Первые Max запросов проходят (но без файла — 400, а не 429).
	for i := 0; i < 2; i++ {
		req := authReq("POST", "/api/media/upload", token)
		resp, err := application.Fiber.Test(req)
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, "request %d should reach handler", i+1)
		resp.Body.Close()
	}

	// ...а следующий получает 429 от upload-лимитера.
	req := authReq("POST", "/api/media/upload", token)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusTooManyRequests, resp.StatusCode)
}
