package handlers_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

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

func setupAdminTestApp(t *testing.T, authUserID uint) (*fiber.App, repository.MediaRepository, repository.TranscodeTaskRepository, string, *services.TranscodeQueue, repository.SettingRepository) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	taskRepo := repository.NewTranscodeTaskRepository(db)
	subRepo := repository.NewSubtitleRepository(db)
	userRepo := repository.NewUserRepository(db)
	settingRepo := repository.NewSettingRepository(db)
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

	handler := handlers.NewAdminHandler(mediaRepo, taskRepo, transQueue, storageCfg, mediaCfg, userRepo, settingRepo)
	app := fiber.New()
	admin := app.Group("/api/admin", func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, authUserID)
		return c.Next()
	}, middleware.RequireAdmin(userRepo))
	admin.Get("/storage", handler.StorageInfo)
	admin.Put("/storage/settings", handler.UpdateStorageSettings)
	admin.Get("/originals", handler.OriginalsList)
	admin.Get("/originals/:name/download", handler.OriginalDownload)
	admin.Delete("/originals/:name", handler.OriginalDelete)
	admin.Get("/transcodes", handler.TranscodesList)
	admin.Post("/transcodes/:id/retry", handler.TranscodeRetry)
	return app, mediaRepo, taskRepo, originalsDir, transQueue, settingRepo
}

func TestAdminStorageInfo(t *testing.T) {
	app, _, _, originalsDir, _, _ := setupAdminTestApp(t, 1)
	require.NoError(t, os.WriteFile(filepath.Join(originalsDir, "a.mkv"), []byte("abc"), 0644))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/storage", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	var body struct {
		Disks []struct {
			Path      string `json:"path"`
			UsedBytes int64  `json:"used_bytes"`
		} `json:"disks"`
		OriginalsBytes int64 `json:"originals_bytes"`
		AutoCleanup    bool  `json:"auto_cleanup"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
	resp.Body.Close()

	assert.False(t, body.AutoCleanup)
	assert.Equal(t, int64(3), body.OriginalsBytes)
	found := false
	for _, disk := range body.Disks {
		if disk.Path == originalsDir {
			found = true
			assert.Equal(t, int64(3), disk.UsedBytes, "used_bytes каталога — размер его файлов")
		}
	}
	assert.True(t, found, "каталог оригиналов должен быть среди дисков")
}

func TestAdminStorageSettingsTogglePersists(t *testing.T) {
	app, _, _, _, queue, settingsRepo := setupAdminTestApp(t, 1)

	req := httptest.NewRequest("PUT", "/api/admin/storage/settings", strings.NewReader(`{"auto_cleanup":true}`))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	var body map[string]bool
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
	resp.Body.Close()
	assert.True(t, body["auto_cleanup"])
	assert.True(t, queue.AutoCleanup())

	stored, ok, err := settingsRepo.GetBool(context.Background(), repository.SettingAutoCleanupOriginals)
	require.NoError(t, err)
	assert.True(t, ok)
	assert.True(t, stored)

	// GET /storage отдаёт состояние очереди, а не конфига.
	resp, err = app.Test(httptest.NewRequest("GET", "/api/admin/storage", nil))
	require.NoError(t, err)
	var storage map[string]any
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&storage))
	resp.Body.Close()
	assert.Equal(t, true, storage["auto_cleanup"])

	// Обратное переключение тоже персистится.
	req = httptest.NewRequest("PUT", "/api/admin/storage/settings", strings.NewReader(`{"auto_cleanup":false}`))
	req.Header.Set("Content-Type", "application/json")
	resp, err = app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	resp.Body.Close()
	assert.False(t, queue.AutoCleanup())
	stored, ok, err = settingsRepo.GetBool(context.Background(), repository.SettingAutoCleanupOriginals)
	require.NoError(t, err)
	assert.True(t, ok)
	assert.False(t, stored)
}

func TestAdminStorageSettingsValidation(t *testing.T) {
	app, _, _, _, _, _ := setupAdminTestApp(t, 1)

	cases := []struct {
		name string
		body string
	}{
		{name: "missing key", body: `{}`},
		{name: "wrong type", body: `{"auto_cleanup":"yes"}`},
		{name: "broken json", body: `{`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("PUT", "/api/admin/storage/settings", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			resp, err := app.Test(req)
			require.NoError(t, err)
			resp.Body.Close()
			assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
		})
	}
}

func TestAdminStorageSettingsRevertsOnSaveError(t *testing.T) {
	queue := &stubTranscodeQueue{}
	settingsRepo := &stubSettingsRepo{err: errors.New("db down")}
	handler := handlers.NewAdminHandler(nil, nil, queue, config.StorageConfig{}, config.MediaConfig{}, nil, settingsRepo)
	app := fiber.New()
	app.Put("/api/admin/storage/settings", handler.UpdateStorageSettings)

	req := httptest.NewRequest("PUT", "/api/admin/storage/settings", strings.NewReader(`{"auto_cleanup":true}`))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusInternalServerError, resp.StatusCode)
	assert.False(t, queue.AutoCleanup(), "несохранённый флаг обязан откатиться")
}

func TestAdminStorageSettingsForbiddenForNonAdmin(t *testing.T) {
	app, _, _, _, _, _ := setupAdminTestApp(t, 2)

	req := httptest.NewRequest("PUT", "/api/admin/storage/settings", strings.NewReader(`{"auto_cleanup":true}`))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}

// stubSettingsRepo — репозиторий с управляемой ошибкой для проверки
// отката флага очереди при неудачной записи.
type stubSettingsRepo struct {
	err    error
	values map[string]string
}

func (s *stubSettingsRepo) Get(_ context.Context, key string) (string, bool, error) {
	if s.err != nil {
		return "", false, s.err
	}
	value, ok := s.values[key]
	return value, ok, nil
}

func (s *stubSettingsRepo) Set(_ context.Context, key, value string) error {
	if s.err != nil {
		return s.err
	}
	if s.values == nil {
		s.values = make(map[string]string)
	}
	s.values[key] = value
	return nil
}

func (s *stubSettingsRepo) GetBool(ctx context.Context, key string) (bool, bool, error) {
	value, ok, err := s.Get(ctx, key)
	if err != nil || !ok {
		return false, false, err
	}
	return value == "true", true, nil
}

func (s *stubSettingsRepo) SetBool(ctx context.Context, key string, value bool) error {
	if value {
		return s.Set(ctx, key, "true")
	}
	return s.Set(ctx, key, "false")
}

func TestAdminForbiddenForNonAdmin(t *testing.T) {
	app, _, _, _, _, _ := setupAdminTestApp(t, 2)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/storage", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}

func TestAdminOriginalsListJoinsTaskAndViews(t *testing.T) {
	app, mediaRepo, taskRepo, originalsDir, _, _ := setupAdminTestApp(t, 1)
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
	app, _, _, originalsDir, _, _ := setupAdminTestApp(t, 1)

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
	app, _, taskRepo, _, queue, _ := setupAdminTestApp(t, 1)
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
	handler := handlers.NewAdminHandler(nil, nil, stub, config.StorageConfig{}, config.MediaConfig{}, nil, nil)
	app.Post("/api/admin/transcodes/:id/retry", handler.TranscodeRetry)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/admin/transcodes/1/retry", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestAdminTranscodeRetryZeroIDIsBadRequest(t *testing.T) {
	app, _, _, _, _, _ := setupAdminTestApp(t, 1)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/admin/transcodes/0/retry", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

type adminTranscodeJSON struct {
	ID         uint    `json:"id"`
	Status     string  `json:"status"`
	Progress   int     `json:"progress"`
	Speed      float64 `json:"speed"`
	ETASeconds int64   `json:"eta_seconds"`
	Error      *string `json:"error"`
	Filename   string  `json:"filename"`
	MediaID    uint    `json:"media_id"`
}

func TestAdminTranscodesList(t *testing.T) {
	app, _, taskRepo, _, queue, _ := setupAdminTestApp(t, 1)
	// Воркер остановлен: иначе он подхватит queued-задания и статусы
	// уплывут из-под assert'ов (как в TestAdminTranscodeRetry).
	queue.Stop()
	ctx := context.Background()

	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{SourcePath: "/q/a.mkv", Filename: "a.mkv", Status: services.TranscodeTaskQueued}))
	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{SourcePath: "/q/b.mkv", Filename: "b.mkv", Status: services.TranscodeTaskProcessing, Progress: 40, Speed: 2, DurationSecs: 100}))
	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{SourcePath: "/q/c.mkv", Filename: "c.mkv", Status: services.TranscodeTaskDone, MediaID: 7}))
	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{SourcePath: "/q/d.mkv", Filename: "d.mkv", Status: services.TranscodeTaskError, ErrorMsg: "boom"}))
	old := time.Now().Add(-services.TranscodeTerminalTTL - 24*time.Hour)
	require.NoError(t, taskRepo.Create(ctx, &models.TranscodeTask{SourcePath: "/q/old.mkv", Filename: "old.mkv", Status: services.TranscodeTaskDone, CreatedAt: old, UpdatedAt: old}))

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/transcodes", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	var items []adminTranscodeJSON
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&items))
	resp.Body.Close()

	// Активные первыми, внутри групп — по id desc; история старше TTL
	// не светится.
	require.Len(t, items, 4)
	assert.Equal(t, []uint{2, 1, 4, 3}, []uint{items[0].ID, items[1].ID, items[2].ID, items[3].ID})
	assert.Equal(t, services.TranscodeTaskProcessing, items[0].Status)
	assert.Equal(t, services.TranscodeTaskQueued, items[1].Status)

	assert.Equal(t, "b.mkv", items[0].Filename)
	assert.Equal(t, 40, items[0].Progress)
	assert.Equal(t, 2.0, items[0].Speed)
	assert.Equal(t, int64(30), items[0].ETASeconds)

	assert.Equal(t, "a.mkv", items[1].Filename)
	assert.Equal(t, int64(0), items[1].ETASeconds)

	require.NotNil(t, items[2].Error)
	assert.Equal(t, "boom", *items[2].Error)
	assert.Equal(t, "d.mkv", items[2].Filename)

	assert.Equal(t, "c.mkv", items[3].Filename)
	assert.Equal(t, uint(7), items[3].MediaID)
	assert.Nil(t, items[3].Error)
}

func TestAdminTranscodesListForbiddenForNonAdmin(t *testing.T) {
	app, _, _, _, _, _ := setupAdminTestApp(t, 2)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/admin/transcodes", nil))
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}
