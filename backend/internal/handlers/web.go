package handlers

import (
	"fmt"
	"mime"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/response"
)

const (
	// Хэшированные бандлы Vite: имя меняется при каждом билде.
	webCacheImmutable = "public, max-age=31536000, immutable"
	// index.html и sw.js проверяются заново при каждом запросе:
	// иначе клиент залипнет на старой версии после деплоя.
	webCacheNoStore = "no-cache"
	// Манифест, иконки, favicon: меняются редко, час — компромисс
	// между свежестью и лишними запросами.
	webCacheStatic = "public, max-age=3600"
)

// WebHandler раздаёт собранный веб-клиент (web/dist) с того же origin,
// что и API: относительный /api и cookie-сессии работают без CORS.
// Регистрируется ПОСЛЕДНИМ, после всех /api-маршрутов.
type WebHandler struct {
	root string
}

// NewWebHandler проверяет каталог из server.web_dist: явная опечатка —
// ошибка старта, а не молчаливый API-only режим.
func NewWebHandler(webDist string) (*WebHandler, error) {
	abs, err := filepath.Abs(webDist)
	if err != nil {
		return nil, fmt.Errorf("web_dist: %w", err)
	}
	info, err := os.Stat(abs)
	if err != nil {
		return nil, fmt.Errorf("web_dist %q: %w", webDist, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("web_dist %q: not a directory", webDist)
	}
	if _, err := os.Stat(filepath.Join(abs, "index.html")); err != nil {
		return nil, fmt.Errorf("web_dist %q: no index.html, is it a built web/dist? %w", webDist, err)
	}
	return &WebHandler{root: abs}, nil
}

// RegisterRoutes вешает SPA-раздачу последним маршрутом приложения:
// всё, что не забрал /api, — адреса клиентского роутера.
func (h *WebHandler) RegisterRoutes(app *fiber.App) {
	app.Get("/*", h.serve)
}

func (h *WebHandler) serve(c *fiber.Ctx) error {
	path := c.Path()
	// Неизвестные API-адреса остаются JSON 404, а не index.html:
	// иначе API-клиенты получали бы 200 с HTML-телом.
	if path == "/api" || strings.HasPrefix(path, "/api/") {
		return response.Error(c, fiber.StatusNotFound, "Not found")
	}
	// Якорим путь корнем: Clean схлопывает "..".
	rel := filepath.Clean("/" + path)
	full := filepath.Join(h.root, rel)
	// Явная проверка границы: путь не должен выходить за пределы h.root.
	if rel2, err := filepath.Rel(h.root, full); err != nil || rel2 == ".." || strings.HasPrefix(rel2, ".."+string(filepath.Separator)) {
		c.Set("Cache-Control", webCacheNoStore)
		return c.SendFile(filepath.Join(h.root, "index.html"))
	}
	// Только regular-файлы. os.Stat следует по симлинку: файл по симлинку
	// внутри web_dist будет отдан как regular-файл. Каталоги и несуществующие
	// пути уходят в SPA-фолбэк. Листинги каталогов не отдаём.
	if info, err := os.Stat(full); err == nil && info.Mode().IsRegular() {
		return h.serveFile(c, rel, full)
	}
	// Хэшированные ассеты не должны получать index.html с 200: это
	// маскирует рассинхрон деплоя и ломает MIME/nosniff.
	if strings.HasPrefix(path, "/assets/") {
		return response.Error(c, fiber.StatusNotFound, "Asset not found")
	}
	// Нет файла — адрес SPA: всегда свежий index.html.
	c.Set("Cache-Control", webCacheNoStore)
	return c.SendFile(filepath.Join(h.root, "index.html"))
}

func (h *WebHandler) serveFile(c *fiber.Ctx, rel, full string) error {
	// Vary нужен всегда: один и тот же URL отдаёт обычный и сжатый ответ.
	c.Set("Vary", "Accept-Encoding")
	switch {
	case rel == "/index.html":
		c.Set("Cache-Control", webCacheNoStore)
	case strings.HasPrefix(rel, "/assets/"):
		c.Set("Cache-Control", webCacheImmutable)
	case filepath.Base(rel) == "sw.js":
		c.Set("Cache-Control", webCacheNoStore)
	case strings.HasSuffix(rel, ".webmanifest"):
		// fasthttp не знает этот тип и перезапишет заголовок своим
		// text/plain — отдаём вручную с правильным типом.
		// #nosec G304 -- full уже проверен на принадлежность web root (IsSubPath).
		data, err := os.ReadFile(full)
		if err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Manifest read error")
		}
		c.Set("Cache-Control", webCacheStatic)
		c.Set("Content-Type", "application/manifest+json")
		return c.Send(data)
	default:
		c.Set("Cache-Control", webCacheStatic)
	}
	if encoded, encoding, ok := precompressed(full, c.Get("Accept-Encoding")); ok {
		c.Set("Content-Encoding", encoding)
		// SendFile выбирает тип по .br/.gz, поэтому возвращаем тип оригинала.
		if contentType := mime.TypeByExtension(filepath.Ext(rel)); contentType != "" {
			c.Set("Content-Type", contentType)
		}
		return c.SendFile(encoded)
	}
	return c.SendFile(full)
}

// precompressed выбирает готовый .br/.gz, созданный scripts/compress-dist.mjs.
// q=0 и неизвестные кодировки игнорируются; brotli предпочтительнее gzip.
func precompressed(full, acceptEncoding string) (path, encoding string, ok bool) {
	accepted := make(map[string]bool)
	for _, part := range strings.Split(acceptEncoding, ",") {
		fields := strings.Split(strings.TrimSpace(part), ";")
		name := strings.ToLower(strings.TrimSpace(fields[0]))
		if name == "" {
			continue
		}
		quality := 1.0
		for _, field := range fields[1:] {
			key, value, found := strings.Cut(strings.TrimSpace(field), "=")
			if !found || !strings.EqualFold(key, "q") {
				continue
			}
			if _, err := fmt.Sscanf(value, "%f", &quality); err != nil {
				quality = 1
			}
		}
		accepted[name] = quality > 0
	}
	for _, candidate := range []struct {
		name string
		ext  string
	}{{"br", ".br"}, {"gzip", ".gz"}} {
		if !accepted[candidate.name] {
			continue
		}
		encoded := full + candidate.ext
		if info, err := os.Stat(encoded); err == nil && info.Mode().IsRegular() {
			return encoded, candidate.name, true
		}
	}
	return "", "", false
}
