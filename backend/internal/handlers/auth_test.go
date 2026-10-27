package handlers_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/app"
	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/middleware"
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
			RefreshExpiry:     720,
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

// loginWithCookies выполняет полный вход через OTP и возвращает пару
// токенов из JSON вместе с выставленными сессионными куками.
func loginWithCookies(t *testing.T, application *app.App, email string) (string, string, []*http.Cookie) {
	t.Helper()

	code, err := application.OTPStore.Generate(email)
	require.NoError(t, err)
	b, _ := json.Marshal(map[string]string{"email": email, "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)
	accessToken, ok := body["token"].(string)
	require.True(t, ok)
	require.NotEmpty(t, accessToken)
	refreshToken, ok := body["refresh_token"].(string)
	require.True(t, ok)
	require.NotEmpty(t, refreshToken)

	return accessToken, refreshToken, resp.Cookies()
}

func findCookie(cookies []*http.Cookie, name string) *http.Cookie {
	for _, c := range cookies {
		if c.Name == name {
			return c
		}
	}
	return nil
}

func TestAuthVerifySetsSessionCookies(t *testing.T) {
	application := newTestAppForAuth(t)

	_, _, cookies := loginWithCookies(t, application, "cookies@example.com")

	access := findCookie(cookies, middleware.CookieAccessToken)
	require.NotNil(t, access, "нет куки flux_access")
	assert.NotEmpty(t, access.Value)
	assert.True(t, access.HttpOnly)
	assert.Equal(t, "/", access.Path)

	refresh := findCookie(cookies, middleware.CookieRefreshToken)
	require.NotNil(t, refresh, "нет куки flux_refresh")
	assert.NotEmpty(t, refresh.Value)
	assert.True(t, refresh.HttpOnly)
	// Долгоживущий refresh-токен нужен только auth-эндпоинтам —
	// браузер не должен слать его на каждый запрос /api/...
	assert.Equal(t, "/api/auth", refresh.Path)
}

func TestAuthMeWithAccessCookie(t *testing.T) {
	application := newTestAppForAuth(t)

	accessToken, _, _ := loginWithCookies(t, application, "me-cookie@example.com")

	// Без заголовка Authorization: доступ только по куке.
	req := httptest.NewRequest("GET", "/api/auth/me", nil)
	req.AddCookie(&http.Cookie{Name: middleware.CookieAccessToken, Value: accessToken})

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)
	assert.Equal(t, "me-cookie@example.com", body["email"])
}

func TestAuthRefreshFromCookie(t *testing.T) {
	application := newTestAppForAuth(t)

	_, refreshToken, _ := loginWithCookies(t, application, "refresh-cookie@example.com")

	// Пустое тело: refresh-токен едет в httpOnly-куке.
	b, _ := json.Marshal(map[string]string{})
	req := httptest.NewRequest("POST", "/api/auth/refresh", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.AddCookie(&http.Cookie{Name: middleware.CookieRefreshToken, Value: refreshToken})

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)
	assert.NotEmpty(t, body["token"])
	assert.NotEmpty(t, body["refresh_token"])

	// Ротация перевыставляет обе куки новой парой.
	rotated := resp.Cookies()
	assert.NotEmpty(t, findCookie(rotated, middleware.CookieAccessToken).Value)
	assert.NotEmpty(t, findCookie(rotated, middleware.CookieRefreshToken).Value)
}

func TestAuthRefreshWithoutBody(t *testing.T) {
	application := newTestAppForAuth(t)

	_, refreshToken, _ := loginWithCookies(t, application, "refresh-nobody@example.com")

	// Тела и Content-Type нет вовсе: только кука.
	req := httptest.NewRequest("POST", "/api/auth/refresh", nil)
	req.AddCookie(&http.Cookie{Name: middleware.CookieRefreshToken, Value: refreshToken})

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	parseJSONResponse(t, resp, &body)
	assert.NotEmpty(t, body["token"])
	assert.NotEmpty(t, body["refresh_token"])
}

func TestAuthVerifyCrossOriginRejected(t *testing.T) {
	application := newTestAppForAuth(t)

	code, err := application.OTPStore.Generate("victim@example.com")
	require.NoError(t, err)
	b, _ := json.Marshal(map[string]string{"email": "victim@example.com", "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "https://evil.example")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	// Сессионные куки не выставляются.
	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieAccessToken))
	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieRefreshToken))
}

func TestAuthVerifySameOriginAllowed(t *testing.T) {
	application := newTestAppForAuth(t)

	code, err := application.OTPStore.Generate("same-origin@example.com")
	require.NoError(t, err)
	b, _ := json.Marshal(map[string]string{"email": "same-origin@example.com", "code": code})
	req := httptest.NewRequest("POST", "/api/auth/verify-code", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	// httptest шлёт Host example.com — Origin того же хоста свой.
	req.Header.Set("Origin", "http://example.com")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestAuthRefreshCrossOriginRejected(t *testing.T) {
	application := newTestAppForAuth(t)

	_, refreshToken, _ := loginWithCookies(t, application, "refresh-xorigin@example.com")

	b, _ := json.Marshal(map[string]string{"refresh_token": refreshToken})
	req := httptest.NewRequest("POST", "/api/auth/refresh", bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Origin", "https://evil.example")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieAccessToken))
	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieRefreshToken))
}

func TestAuthRefreshCrossOriginFormRejected(t *testing.T) {
	application := newTestAppForAuth(t)

	_, refreshToken, _ := loginWithCookies(t, application, "refresh-xform@example.com")

	// Реалистичный вектор login CSRF: обычная HTML-форма шлёт
	// application/x-www-form-urlencoded без префлайта.
	form := strings.NewReader("RefreshToken=" + refreshToken)
	req := httptest.NewRequest("POST", "/api/auth/refresh", form)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Origin", "https://evil.example")

	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieAccessToken))
	assert.Nil(t, findCookie(resp.Cookies(), middleware.CookieRefreshToken))
}

func TestAuthLogoutClearsCookies(t *testing.T) {
	application := newTestAppForAuth(t)

	accessToken, _, _ := loginWithCookies(t, application, "logout-cookie@example.com")

	req := httptest.NewRequest("POST", "/api/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := application.Fiber.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	for _, name := range []string{middleware.CookieAccessToken, middleware.CookieRefreshToken} {
		cleared := findCookie(resp.Cookies(), name)
		require.NotNil(t, cleared, "нет куки %s", name)
		assert.Empty(t, cleared.Value)
		expired := cleared.MaxAge <= 0 ||
			(!cleared.Expires.IsZero() && cleared.Expires.Before(time.Now()))
		assert.True(t, expired, "кука %s должна быть истёкшей", name)
	}
}
