package handlers_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/app"
	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/services"
)

func newTestAppForAuth(t *testing.T) *app.App {
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
	application, err := app.New(cfg, "test")
	require.NoError(t, err)
	t.Cleanup(func() { application.Shutdown() })
	return application
}

func parseJSONResponse(t *testing.T, resp *http.Response, v interface{}) {
	t.Helper()
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	if v != nil {
		require.NoError(t, json.Unmarshal(body, v), "body: %s", string(body))
	}
}

func TestAuthLoginSuccess(t *testing.T) {
	application := newTestAppForAuth(t)

	// Generate a code using the app's OTP store
	code, err := application.OTPStore.Generate("test@example.com")
	require.NoError(t, err)

	// Use the code in a single request to the handler
	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Parse response to get token
	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)

	assert.NotEmpty(t, body["token"])

	user, ok := body["user"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "test@example.com", user["email"])
}

func TestAuthLoginInvalidCredentials(t *testing.T) {
	application := newTestAppForAuth(t)

	// Try to verify with invalid code
	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": "000000"})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestAuthVerifyEmptyCode(t *testing.T) {
	application := newTestAppForAuth(t)

	// Try to verify with empty code (B2 fix)
	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": ""})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestAuthRegisterFirstUser(t *testing.T) {
	application := newTestAppForAuth(t)

	emailAddr := "admin@example.com"

	// Generate a code using the app's OTP store
	code, err := application.OTPStore.Generate(emailAddr)
	require.NoError(t, err)

	// Use the code in a single request to the handler
	b, _ := json.Marshal(map[string]string{"email": emailAddr, "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	// Verify first user is admin by checking the response
	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)

	user, ok := body["user"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, emailAddr, user["email"])
	assert.True(t, user["is_admin"].(bool))
}

func TestAuthRegisterSecondUser(t *testing.T) {
	application := newTestAppForAuth(t)

	// Create first user (admin)
	code1, err := application.OTPStore.Generate("admin@example.com")
	require.NoError(t, err)

	b1, _ := json.Marshal(map[string]string{"email": "admin@example.com", "code": code1})
	req1 := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b1))
	req1.Header.Set("Content-Type", "application/json")

	resp1, err := application.Fiber.Test(req1)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp1.StatusCode)
	resp1.Body.Close()

	// Create second user (regular user)
	code2, err := application.OTPStore.Generate("user@example.com")
	require.NoError(t, err)

	b2, _ := json.Marshal(map[string]string{"email": "user@example.com", "code": code2})
	req2 := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b2))
	req2.Header.Set("Content-Type", "application/json")

	resp2, err := application.Fiber.Test(req2)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp2.StatusCode)

	// Verify second user is not admin by checking the response
	var body map[string]interface{}
	parseJSONResponse(t, resp2, &body)

	user, ok := body["user"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "user@example.com", user["email"])
	assert.False(t, user["is_admin"].(bool))
}

func newAuthHandlerForTest(t *testing.T, cfg *config.Config) (*handlers.AuthHandler, *services.OTPStore) {
	t.Helper()
	otp := services.NewOTPStore(5*time.Minute, 6, 1000)
	return handlers.NewAuthHandler(nil, nil, otp, nil, nil, cfg), otp
}

func TestAuthRequestCodeNotAllowedEmail(t *testing.T) {
	cfg := &config.Config{
		Server: config.ServerConfig{Debug: true},
		Auth: config.AuthConfig{
			AllowedEmails:     []string{"allowed@example.com"},
			AllowUnknownEmail: false,
			CodeExpiry:        300,
			CodeLength:        6,
			MaxOTPEntries:     1000,
		},
	}
	h, otp := newAuthHandlerForTest(t, cfg)
	app := fiber.New()
	app.Post("/request-code", h.RequestCode)

	b, _ := json.Marshal(map[string]string{"email": "unknown@example.com"})
	req := httptest.NewRequest("POST", "/request-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	require.NoError(t, err)
	// Перечисление allowlist закрыто: неразрешённому email отвечаем
	// таким же успешным ответом.
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var parsed map[string]interface{}
	parseJSONResponse(t, resp, &parsed)
	assert.Equal(t, "Code sent successfully", parsed["message"])
	// В debug-режиме разрешённым email код попадает в ответ — здесь кода
	// быть не должно: он вообще не генерировался.
	_, hasCode := parsed["code"]
	assert.False(t, hasCode, "code must not be returned for disallowed email")

	// OTP-стор не должен хранить запись для неразрешённого email.
	assert.False(t, otp.Verify("unknown@example.com", "000000"))
}

func TestAuthRequestCodeNormalizedEmail(t *testing.T) {
	cfg := &config.Config{
		Server: config.ServerConfig{Debug: true},
		Auth: config.AuthConfig{
			AllowedEmails:     []string{"user@example.com"},
			AllowUnknownEmail: false,
			CodeExpiry:        300,
			CodeLength:        6,
			MaxOTPEntries:     1000,
		},
	}
	h, _ := newAuthHandlerForTest(t, cfg)
	app := fiber.New()
	app.Post("/request-code", h.RequestCode)

	// Display-name и регистр нормализуются: "User <USER@example.com>"
	// должен совпасть с allowlist по голому адресу.
	b, _ := json.Marshal(map[string]string{"email": "User <USER@example.com>"})
	req := httptest.NewRequest("POST", "/request-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var parsed map[string]interface{}
	parseJSONResponse(t, resp, &parsed)
	assert.Contains(t, parsed, "code", "code must be returned for allowed email in debug mode")
}

func TestAuthLogoutWithoutBody(t *testing.T) {
	application := newTestAppForAuth(t)

	// Login to get an access token.
	code, err := application.OTPStore.Generate("test@example.com")
	require.NoError(t, err)
	b, _ := json.Marshal(map[string]string{"email": "test@example.com", "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)

	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)
	token, ok := body["token"].(string)
	require.True(t, ok)

	// Logout без тела выполняет полный выход — не 400.
	req = httptest.NewRequest("POST", "/api/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err = application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}
