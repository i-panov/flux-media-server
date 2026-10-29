package handlers_test

import (
	"context"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupAdminTestApp(t *testing.T, authUserID uint) (*fiber.App, repository.MediaRepository, repository.TranscodeTaskRepository, string, *services.TranscodeQueue) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	taskRepo := repository.NewTranscodeTaskRepository(db)
	subRepo := repository.NewSubtitleRepository(db)
	userRepo := repository.NewUserRepository(db)
	// Первый созданный пользователь автоматически становится админом
	// (промоушен в userRepo.Create), второй — обычный.
	require.NoError(t, userRepo.Create(context.Background(), &models.User{ID: 1, Email: "admin@test.com"}))
	require.NoError(t, userRepo.Create(context.Background(), &models.User{ID: 2, Email: "user@test.com"}))
	thumbSvc := services.NewThumbnailService(filepath.Join(t.TempDir(), "thumbs"))

	originalsDir := filepath.Join(t.TempDir(), "originals")
	require.NoError(t, os.MkdirAll(originalsDir, 0755))
	storageCfg := config.StorageConfig{OriginalsDir: originalsDir, TempDir: t.TempDir()}
	mediaCfg := config.MediaConfig{VideoPath: t.TempDir(), AudioPath: t.TempDir()}

	transQueue := services.NewTranscodeQueue(
		context.Background(),
		services.TranscodeWorkerConfig{OriginalsDir: originalsDir, TempDir: storageCfg.TempDir},
		taskRepo, mediaRepo, subRepo, thumbSvc, nil,
	)
	t.Cleanup(transQueue.Stop)

	handler := handlers.NewAdminHandler(mediaRepo, taskRepo, transQueue, storageCfg, mediaCfg)
	app := fiber.New()
	admin := app.Group("/api/admin", func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, authUserID)
		return c.Next()
	}, middleware.RequireAdmin(userRepo))
	admin.Get("/storage", handler.StorageInfo)
	admin.Get("/originals", handler.OriginalsList)
	admin.Get("/originals/:name/download", handler.OriginalDownload)
	admin.Delete("/originals/:name", handler.OriginalDelete)
	admin.Post("/transcodes/:id/retry", handler.TranscodeRetry)
	return app, mediaRepo, taskRepo, originalsDir, transQueue
}

func TestAdminStorageInfo(t *testing.T) {
	app, _, _, _, _ := setupAdminTestApp(t, 1)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/storage", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Contains(t, string(body), `"disks"`)
	assert.Contains(t, string(body), `"auto_cleanup":false`)
}

func TestAdminForbiddenForNonAdmin(t *testing.T) {
	app, _, _, _, _ := setupAdminTestApp(t, 2)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/storage", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}

func TestAdminOriginalsListJoinsTaskAndViews(t *testing.T) {
	app, mediaRepo, taskRepo, originalsDir, _ := setupAdminTestApp(t, 1)
	ctx := context.Background()

	require.NoError(t, os.WriteFile(filepath.Join(originalsDir, "a.mkv"), []byte("aaa"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(originalsDir, "b.mkv"), []byte("b"), 0644))

	mediaPath := filepath.Join(t.TempDir(), "a.mp4")
	require.NoError(t, os.WriteFile(mediaPath, []byte("video"), 0644))
	media := &models.Media{Title: "A", Type: models.MediaTypeVideo, FilePath: mediaPath}
	require.NoError(t, mediaRepo.Create(ctx, media))
	require.NoError(t, mediaRepo.IncrementViews(ctx, media.ID))
	require.NoError(t, mediaRepo.IncrementViews(ctx, media.ID))
	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{
		SourcePath: filepath.Join(originalsDir, "a.mkv"), Filename: "a.mkv",
		Status: services.TranscodeTaskDone, MediaID: media.ID,
	}))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/originals", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	// b.mkv без просмотров и меньше — но сортировка: views ASC, значит a.mkv (2 просмотра) после b.mkv.
	text := string(body)
	assert.Contains(t, text, `"name":"a.mkv"`)
	assert.Contains(t, text, `"status":"done"`)
	assert.Contains(t, text, `"views":2`)
	assert.Contains(t, text, `"name":"b.mkv"`)
	assert.Contains(t, text, `"status":"untracked"`)
	assert.Less(t, strings.Index(text, `"b.mkv"`), strings.Index(text, `"a.mkv"`))
}

func TestAdminOriginalDownloadAndDelete(t *testing.T) {
	app, _, _, originalsDir, _ := setupAdminTestApp(t, 1)

	require.NoError(t, os.WriteFile(filepath.Join(originalsDir, "film.mkv"), []byte("0123456789"), 0644))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/originals/film.mkv/download", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Contains(t, resp.Header.Get("Content-Disposition"), "attachment")
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Equal(t, "0123456789", string(body))

	// Обход через .. нормализуется маршрутизатором до хендлера —
	// такой запрос никуда не резолвится (404, не 200).
	resp, err = app.Test(httptest.NewRequest("GET", "/api/admin/originals/../x/download", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/admin/originals/film.mkv", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)
	_, err = os.Stat(filepath.Join(originalsDir, "film.mkv"))
	require.True(t, os.IsNotExist(err))

	// Повторное удаление — тоже успех (идемпотентный DELETE),
	// а не 404: файл уже отсутствует, цель достигнута.
	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/admin/originals/film.mkv", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)
}

func TestAdminTranscodeRetry(t *testing.T) {
	app, _, taskRepo, _, queue := setupAdminTestApp(t, 1)
	// Воркер остановлен: иначе он тут же подхватит requeued-задание
	// и статус уплывёт из-под assert'а.
	queue.Stop()
	ctx := context.Background()

	task := &models.TranscodeTask{SourcePath: "/q/x.mkv", Filename: "x.mkv", Status: services.TranscodeTaskError, Attempts: 3, ErrorMsg: "boom"}
	require.NoError(t, taskRepo.Create(ctx, task))

	resp, err := app.Test(httptest.NewRequest("POST", "/api/admin/transcodes/1/retry", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusAccepted, resp.StatusCode)

	got, err := taskRepo.Get(ctx, task.ID)
	require.NoError(t, err)
	assert.Equal(t, services.TranscodeTaskQueued, got.Status)
	assert.Equal(t, 0, got.Attempts)

	// Повторное — уже не failed.
	resp, err = app.Test(httptest.NewRequest("POST", "/api/admin/transcodes/1/retry", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestAdminTranscodeRetryConflict(t *testing.T) {
	// Гонка проиграна (Retry вернул конфликт) — 409 с понятным текстом.
	stub := &stubTranscodeQueue{retryErr: services.ErrTranscodeConflict}
	app := fiber.New()
	handler := handlers.NewAdminHandler(nil, nil, stub, config.StorageConfig{}, config.MediaConfig{})
	app.Post("/api/admin/transcodes/:id/retry", handler.TranscodeRetry)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/admin/transcodes/1/retry", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}
