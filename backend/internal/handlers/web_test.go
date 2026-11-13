package handlers_test

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/handlers"
)

const webIndexBody = "<!doctype html><html>flux</html>"
const webAssetBody = "console.log('app')"

// webTestDist собирает минимальный web/dist: индекс, хэшированный бандл,
// sw.js, манифест, иконка и подкаталог без индекса.
func webTestDist(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(root, "index.html"), []byte(webIndexBody), 0644))
	require.NoError(t, os.MkdirAll(filepath.Join(root, "assets"), 0755))
	require.NoError(t, os.WriteFile(filepath.Join(root, "assets", "app-abc123.js"), []byte(webAssetBody), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(root, "sw.js"), []byte("sw"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(root, "manifest.webmanifest"), []byte(`{"name":"flux"}`), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(root, "icon-192.png"), []byte("png"), 0644))
	require.NoError(t, os.MkdirAll(filepath.Join(root, "nested"), 0755))
	return root
}

func webTestApp(t *testing.T, root string) *fiber.App {
	t.Helper()
	handler, err := handlers.NewWebHandler(root)
	require.NoError(t, err)
	app := fiber.New()
	// API регистрируется раньше веба и остаётся приоритетнее.
	app.Get("/api/thing", func(c *fiber.Ctx) error {
		return c.SendString("thing")
	})
	handler.RegisterRoutes(app)
	return app
}

func webGet(t *testing.T, app *fiber.App, path string) (int, http.Header, string) {
	t.Helper()
	resp, err := app.Test(httptest.NewRequest(http.MethodGet, path, nil))
	require.NoError(t, err)
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	return resp.StatusCode, resp.Header, string(body)
}

func TestWebHandlerValidation(t *testing.T) {
	_, err := handlers.NewWebHandler(filepath.Join(t.TempDir(), "missing"))
	require.Error(t, err)

	file := filepath.Join(t.TempDir(), "file")
	require.NoError(t, os.WriteFile(file, []byte("x"), 0644))
	_, err = handlers.NewWebHandler(file)
	require.Error(t, err)

	empty := t.TempDir()
	_, err = handlers.NewWebHandler(empty)
	require.ErrorContains(t, err, "index.html")
}

func TestWebServesIndexAndFallback(t *testing.T) {
	app := webTestApp(t, webTestDist(t))

	for _, path := range []string{"/", "/video/42", "/nested/", "/index.html", "/favicon-missing.svg"} {
		status, header, body := webGet(t, app, path)
		assert.Equal(t, fiber.StatusOK, status, path)
		assert.Equal(t, webIndexBody, body, path)
		assert.Equal(t, "no-cache", header.Get("Cache-Control"), path)
	}
}

func TestWebMissingAssetIs404(t *testing.T) {
	app := webTestApp(t, webTestDist(t))
	status, _, body := webGet(t, app, "/assets/missing.js")
	assert.Equal(t, fiber.StatusNotFound, status)
	assert.NotEqual(t, webIndexBody, body)
}

func TestWebAssetCaching(t *testing.T) {
	app := webTestApp(t, webTestDist(t))

	status, header, body := webGet(t, app, "/assets/app-abc123.js")
	assert.Equal(t, fiber.StatusOK, status)
	assert.Equal(t, webAssetBody, body)
	assert.Equal(t, "public, max-age=31536000, immutable", header.Get("Cache-Control"))

	status, header, _ = webGet(t, app, "/sw.js")
	assert.Equal(t, fiber.StatusOK, status)
	assert.Equal(t, "no-cache", header.Get("Cache-Control"))

	status, header, _ = webGet(t, app, "/icon-192.png")
	assert.Equal(t, fiber.StatusOK, status)
	assert.Equal(t, "public, max-age=3600", header.Get("Cache-Control"))
}

func TestWebManifestContentType(t *testing.T) {
	app := webTestApp(t, webTestDist(t))

	status, header, body := webGet(t, app, "/manifest.webmanifest")
	assert.Equal(t, fiber.StatusOK, status)
	assert.Equal(t, `{"name":"flux"}`, body)
	assert.Equal(t, "application/manifest+json", header.Get("Content-Type"))
}

func TestWebTraversalStaysInsideRoot(t *testing.T) {
	parent := t.TempDir()
	outside := filepath.Join(parent, "secret.txt")
	require.NoError(t, os.WriteFile(outside, []byte("top-secret-marker"), 0644))
	root := filepath.Join(parent, "dist")
	require.NoError(t, os.MkdirAll(root, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(root, "index.html"), []byte(webIndexBody), 0644))

	app := webTestApp(t, root)
	for _, path := range []string{"/../secret.txt", "/%2e%2e/secret.txt", "/assets/../../secret.txt"} {
		_, _, body := webGet(t, app, path)
		assert.NotContains(t, body, "top-secret-marker", path)
	}
}

func TestWebLeavesAPIAlone(t *testing.T) {
	app := webTestApp(t, webTestDist(t))

	status, _, body := webGet(t, app, "/api/thing")
	assert.Equal(t, fiber.StatusOK, status)
	assert.Equal(t, "thing", body)

	// Неизвестный API-адрес — JSON 404, а не index.html.
	status, _, body = webGet(t, app, "/api/nope")
	assert.Equal(t, fiber.StatusNotFound, status)
	assert.True(t, strings.Contains(body, "error"), body)
}

func TestWebPrecompressedAssets(t *testing.T) {
	root := webTestDist(t)
	asset := filepath.Join(root, "assets", "app-abc123.js")
	require.NoError(t, os.WriteFile(asset+".br", []byte("brotli-body"), 0644))
	require.NoError(t, os.WriteFile(asset+".gz", []byte("gzip-body"), 0644))
	app := webTestApp(t, root)

	req := httptest.NewRequest(http.MethodGet, "/assets/app-abc123.js", nil)
	req.Header.Set("Accept-Encoding", "gzip, br")
	resp, err := app.Test(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, "br", resp.Header.Get("Content-Encoding"))
	assert.Equal(t, "Accept-Encoding", resp.Header.Get("Vary"))
	assert.Equal(t, "text/javascript; charset=utf-8", resp.Header.Get("Content-Type"))
	assert.Equal(t, "brotli-body", string(body))

	req = httptest.NewRequest(http.MethodGet, "/assets/app-abc123.js", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	resp, err = app.Test(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	body, err = io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, "gzip", resp.Header.Get("Content-Encoding"))
	assert.Equal(t, "gzip-body", string(body))
}
