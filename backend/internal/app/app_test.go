package app

import (
	"bytes"
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
		Server:   config.ServerConfig{Port: 0, Debug: true},
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
	t.Cleanup(func() { application.Shutdown() })
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

	resp, err := application.Fiber.Test(httptest.NewRequest("GET", "/health", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]string
	parseResp(t, resp, &body)
	assert.Equal(t, "ok", body["status"])
	assert.Equal(t, "test", body["version"])
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

func TestAuthRequestCodeForbidden(t *testing.T) {
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
	t.Cleanup(application.Shutdown)

	b, _ := json.Marshal(map[string]string{"email": "unknown@example.com"})
	req := testReq("POST", "/api/auth/request-code", bytes.NewReader(b))

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
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

// --- Libraries ---

func TestLibraryCRUD(t *testing.T) {
	application := newTestApp(t)
	token := getAuthToken(t, application, "lib@example.com")

	// Create
	b, _ := json.Marshal(map[string]interface{}{"name": "Movies", "type": "video"})
	req := testReq("POST", "/api/libraries", bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusCreated, resp.StatusCode)

	var created map[string]interface{}
	parseResp(t, resp, &created)
	assert.Equal(t, "Movies", created["name"])

	// List
	resp2, err := application.Fiber.Test(authReq("GET", "/api/libraries", token))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp2.StatusCode)

	var list []map[string]interface{}
	parseResp(t, resp2, &list)
	assert.GreaterOrEqual(t, len(list), 1)
	found := false
	for _, l := range list {
		if l["name"] == "Movies" {
			found = true
			break
		}
	}
	assert.True(t, found, "Expected to find 'Movies' in library list")
}

// --- Scan status ---

func TestScanStatus(t *testing.T) {
	application := newTestApp(t)
	token := getAuthToken(t, application, "scan@example.com")

	// Create library
	b, _ := json.Marshal(map[string]interface{}{"name": "TV", "type": "video"})
	req := testReq("POST", "/api/libraries", bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	require.Equal(t, fiber.StatusCreated, resp.StatusCode)
	resp.Body.Close()

	// Check scan status
	resp2, err := application.Fiber.Test(authReq("GET", "/api/libraries/1/scan-status", token))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp2.StatusCode)

	var status map[string]interface{}
	parseResp(t, resp2, &status)
	assert.Equal(t, false, status["running"])
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
	t.Cleanup(application.Shutdown)

	_, err = application.OTPStore.Generate("a@test.com")
	require.NoError(t, err)
	_, err = application.OTPStore.Generate("b@test.com")
	require.NoError(t, err)

	_, err = application.OTPStore.Generate("c@test.com")
	assert.ErrorIs(t, err, services.ErrOTPStoreFull)
}
