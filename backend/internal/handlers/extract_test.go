package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

// stubExtractQueue — очередь без ffmpeg: хендлер тестируется отдельно
// от сервиса (сервис покрыт extract_test.go, ffmpeg-пути — со скипом).
type stubExtractQueue struct {
	enqueueID  uint64
	enqueueErr error
	status     string
	errMsg     string
	mediaID    uint
	ok         bool
	cancelErr  error
	enqueued   []uint
	// forceUnavailable — эмуляция сервера без ffmpeg (503).
	forceUnavailable bool
}

func (s *stubExtractQueue) Enqueue(sourceID uint) (uint64, error) {
	s.enqueued = append(s.enqueued, sourceID)
	if s.enqueueErr != nil {
		return 0, s.enqueueErr
	}
	return s.enqueueID, nil
}

func (s *stubExtractQueue) Get(id uint64) (string, string, uint, bool) {
	return s.status, s.errMsg, s.mediaID, s.ok
}

func (s *stubExtractQueue) Cancel(id uint64) error {
	return s.cancelErr
}

func (s *stubExtractQueue) Available() bool {
	return !s.forceUnavailable
}

func uintPtr(v uint) *uint { return &v }

func setupExtractTestApp(t *testing.T, queue ExtractQueue) (*fiber.App, *gorm.DB) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	// Видео id=1 и несвязанное аудио id=2.
	require.NoError(t, db.Create(&models.Media{
		Title:    "Clip",
		Type:     models.MediaTypeVideo,
		FilePath: "/clip.mp4",
	}).Error)
	require.NoError(t, db.Create(&models.Media{
		Title:    "Song",
		Type:     models.MediaTypeAudio,
		FilePath: "/song.mp3",
	}).Error)

	handler := NewExtractHandler(mediaRepo, queue)
	app := fiber.New()

	app.Use(func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, uint(1))
		return c.Next()
	})

	app.Post("/api/media/:id/extract", handler.Extract)
	app.Get("/api/media/extract/:id", handler.ExtractStatus)
	app.Delete("/api/media/extract/:id", handler.CancelExtract)
	app.Get("/api/media/:id/extracted", handler.Extracted)

	return app, db
}

func TestExtractHandler_RejectsMissingAndAudioSource(t *testing.T) {
	app, _ := setupExtractTestApp(t, &stubExtractQueue{})

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/999/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("POST", "/api/media/2/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestExtractHandler_EnqueuesVideo(t *testing.T) {
	stub := &stubExtractQueue{enqueueID: 42}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	assert.Equal(t, []uint{1}, stub.enqueued)
}

func TestExtractHandler_ReturnsLinkedTrackWithoutJob(t *testing.T) {
	stub := &stubExtractQueue{enqueueID: 42}
	app, db := setupExtractTestApp(t, stub)

	// Связка уже есть: POST отдаёт готовый трек, задание не создаётся.
	require.NoError(t, db.Create(&models.Media{
		Title:         "Clip",
		Type:          models.MediaTypeAudio,
		FilePath:      "/clip.m4a",
		SourceMediaID: uintPtr(1),
	}).Error)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Empty(t, stub.enqueued)
}

func TestExtractHandler_StatusShapes(t *testing.T) {
	stub := &stubExtractQueue{status: services.ExtractJobProcessing, ok: true}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/extract/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	stub.ok = false
	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/extract/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestExtractHandler_CancelShapes(t *testing.T) {
	stub := &stubExtractQueue{}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/extract/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)

	stub.cancelErr = services.ErrExtractJobNotFound
	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/media/extract/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	stub.cancelErr = services.ErrExtractJobDone
	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/media/extract/5", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestExtractHandler_InvalidIDs(t *testing.T) {
	stub := &stubExtractQueue{}
	app, _ := setupExtractTestApp(t, stub)

	// Невалидный id видео — 400, задания нет.
	for _, target := range []string{
		"/api/media/abc/extract",
		"/api/media/0/extract",
	} {
		resp, err := app.Test(httptest.NewRequest("POST", target, nil))
		require.NoError(t, err)
		assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode, target)
	}
	// Невалидный id джоба — 400 и на статусе, и на отмене.
	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/extract/abc", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/media/extract/-1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Empty(t, stub.enqueued)
}

func TestExtractHandler_ConcurrentPostsShareOneJob(t *testing.T) {
	// Два параллельных POST одного видео — один джоб: дедуп in-flight
	// в Enqueue, а не два ffmpeg на источник. workers=0: джобы висят
	// в queued, гонка детерминирована.
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{
		Title:    "Clip",
		Type:     models.MediaTypeVideo,
		FilePath: "/clip.mp4",
	}).Error)

	svc := services.NewExtractService(
		context.Background(),
		mediaRepo,
		services.NewThumbnailService(t.TempDir()),
		t.TempDir(),
		0,
		10,
	)
	t.Cleanup(svc.Stop)
	if !svc.Available() {
		t.Skip("ffmpeg/ffprobe not available")
	}

	handler := NewExtractHandler(mediaRepo, svc)
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, uint(1))
		return c.Next()
	})
	app.Post("/api/media/:id/extract", handler.Extract)

	decodeJobID := func(t *testing.T, resp *http.Response) float64 {
		t.Helper()
		require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
		var body map[string]any
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
		id, ok := body["job_id"].(float64)
		require.True(t, ok)
		return id
	}

	resp1, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	resp2, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)

	assert.Equal(t, decodeJobID(t, resp1), decodeJobID(t, resp2))
}

func TestExtractHandler_ConcurrentPostsShareOneJobParallel(t *testing.T) {
	// Те же два POST, но по-настоящему параллельно: app.Test
	// горутинобезопасен, дедуп держится мьютексом Enqueue.
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{
		Title:    "Clip",
		Type:     models.MediaTypeVideo,
		FilePath: "/clip.mp4",
	}).Error)

	svc := services.NewExtractService(
		context.Background(),
		mediaRepo,
		services.NewThumbnailService(t.TempDir()),
		t.TempDir(),
		0,
		10,
	)
	t.Cleanup(svc.Stop)
	if !svc.Available() {
		t.Skip("ffmpeg/ffprobe not available")
	}

	handler := NewExtractHandler(mediaRepo, svc)
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, uint(1))
		return c.Next()
	})
	app.Post("/api/media/:id/extract", handler.Extract)

	const n = 8
	ids := make([]float64, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
			assert.NoError(t, err)
			var body map[string]any
			assert.NoError(t, json.NewDecoder(resp.Body).Decode(&body))
			id, ok := body["job_id"].(float64)
			assert.True(t, ok)
			ids[i] = id
		}(i)
	}
	wg.Wait()

	for _, id := range ids[1:] {
		assert.Equal(t, ids[0], id)
	}
}

func TestExtractHandler_CancelledJobStatusIs404(t *testing.T) {
	// Отмена стирает задание: статус превращается в 404. Клиент отличает
	// отмену локальным флагом, а не кодом (см. ExtractController).
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))
	mediaRepo := repository.NewMediaRepository(db)
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)
	require.NoError(t, db.Create(&models.Media{
		Title:    "Clip",
		Type:     models.MediaTypeVideo,
		FilePath: "/clip.mp4",
	}).Error)

	svc := services.NewExtractService(
		context.Background(),
		mediaRepo,
		services.NewThumbnailService(t.TempDir()),
		t.TempDir(),
		0,
		10,
	)
	t.Cleanup(svc.Stop)
	if !svc.Available() {
		t.Skip("ffmpeg/ffprobe not available")
	}

	handler := NewExtractHandler(mediaRepo, svc)
	app := fiber.New()
	app.Use(func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, uint(1))
		return c.Next()
	})
	app.Post("/api/media/:id/extract", handler.Extract)
	app.Get("/api/media/extract/:id", handler.ExtractStatus)
	app.Delete("/api/media/extract/:id", handler.CancelExtract)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/media/extract/1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/extract/1", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestExtractHandler_UnavailableWithoutFFmpeg(t *testing.T) {
	stub := &stubExtractQueue{forceUnavailable: true}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusServiceUnavailable, resp.StatusCode)
	assert.Empty(t, stub.enqueued)
}

func TestExtractHandler_QueueFullIs429(t *testing.T) {
	stub := &stubExtractQueue{enqueueErr: services.ErrExtractQueueFull}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("POST", "/api/media/1/extract", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusTooManyRequests, resp.StatusCode)
}

func TestExtractHandler_StatusDoneShapes(t *testing.T) {
	// done + живая запись → media присутствует.
	stub := &stubExtractQueue{
		status:  services.ExtractJobDone,
		mediaID: 2,
		ok:      true,
	}
	app, _ := setupExtractTestApp(t, stub)

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/extract/5", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Contains(t, readBody(t, resp), `"id":2`)

	// done + удалённая запись → media:null, а не сбой API.
	stub.mediaID = 999
	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/extract/5", nil))
	require.NoError(t, err)
	require.Equal(t, fiber.StatusOK, resp.StatusCode)
	assert.Contains(t, readBody(t, resp), `"media":null`)
}

func TestExtractHandler_ExtractedLink(t *testing.T) {
	stub := &stubExtractQueue{}
	app, db := setupExtractTestApp(t, stub)

	// Связки нет — 404, экран показывает кнопку извлечения.
	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/1/extracted", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	require.NoError(t, db.Create(&models.Media{
		Title:         "Clip",
		Type:          models.MediaTypeAudio,
		FilePath:      "/clip.m4a",
		SourceMediaID: uintPtr(1),
	}).Error)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/1/extracted", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}
