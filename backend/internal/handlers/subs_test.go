package handlers_test

import (
	"context"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/models"
	"flux/internal/repository"
)

func setupSubsTestApp(t *testing.T) (*fiber.App, repository.MediaRepository, repository.SubtitleRepository, string) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	subRepo := repository.NewSubtitleRepository(db)

	libraryPath := t.TempDir()
	mediaCfg := config.MediaConfig{VideoPath: libraryPath, AudioPath: libraryPath}
	handler := handlers.NewSubsHandler(mediaRepo, subRepo, mediaCfg)

	app := fiber.New()
	app.Get("/api/media/:id/subs", handler.ListSubs)
	app.Get("/api/media/:id/subs/:lang", handler.ServeSub)
	return app, mediaRepo, subRepo, libraryPath
}

func TestSubsListAndServe(t *testing.T) {
	app, mediaRepo, subRepo, libraryPath := setupSubsTestApp(t)
	ctx := context.Background()

	vttPath := filepath.Join(libraryPath, "film.rus.vtt")
	require.NoError(t, os.WriteFile(vttPath, []byte("WEBVTT\n\n00:00.000 --> 00:01.000\nHi\n"), 0644))

	media := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: filepath.Join(libraryPath, "film.mp4")}
	require.NoError(t, mediaRepo.Create(ctx, media))
	require.NoError(t, subRepo.ReplaceForMedia(ctx, media.ID, []models.Subtitle{{Lang: "rus", Path: vttPath}}))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/subs", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Contains(t, string(body), `"lang":"rus"`)
	assert.Contains(t, string(body), "/api/media/1/subs/rus")

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/1/subs/rus", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Equal(t, "text/vtt; charset=utf-8", resp.Header.Get("Content-Type"))
	body, err = io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Contains(t, string(body), "WEBVTT")
}

func TestSubsNotFoundCases(t *testing.T) {
	app, mediaRepo, subRepo, libraryPath := setupSubsTestApp(t)
	ctx := context.Background()

	// Нет медиа — 404 и на списке, и на файле.
	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/999/subs", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	// Плохой идентификатор языка — 400, неизвестный — 404.
	media := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: filepath.Join(libraryPath, "film.mp4")}
	require.NoError(t, mediaRepo.Create(ctx, media))
	require.NoError(t, subRepo.ReplaceForMedia(ctx, media.ID, nil))

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/1/subs/../x", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/1/subs/eng", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestSubsOutsideLibraryRejected(t *testing.T) {
	app, mediaRepo, subRepo, libraryPath := setupSubsTestApp(t)
	ctx := context.Background()

	// Строка указывает за пределы библиотеки (подмена в БД):
	// список отдаст, serve — 404.
	outside := filepath.Join(t.TempDir(), "evil.rus.vtt")
	require.NoError(t, os.WriteFile(outside, []byte("WEBVTT\n"), 0644))
	media := &models.Media{Title: "V", Type: models.MediaTypeVideo, FilePath: filepath.Join(libraryPath, "film.mp4")}
	require.NoError(t, mediaRepo.Create(ctx, media))
	require.NoError(t, subRepo.ReplaceForMedia(ctx, media.ID, []models.Subtitle{{Lang: "rus", Path: outside}}))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/subs/rus", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}
