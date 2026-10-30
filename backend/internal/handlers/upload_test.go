package handlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

// setupUploadTest создаёт приложение с очередью обработки загрузок.
// workers=0 останавливает обработку — задания остаются в статусе queued
// (нужно для тестов отмены и переполнения очереди).
// Видео-загрузки идут в карантин через stubTranscodeQueue (настоящий
// транскод с ffmpeg тестируется на уровне сервисов).
func setupUploadTest(t *testing.T, workers, queueLimit int) (*fiber.App, repository.MediaRepository, string, *stubTranscodeQueue, string, func()) {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	mediaRepo := repository.NewMediaRepository(db)

	tempDir := t.TempDir()
	libraryPath := filepath.Join(tempDir, "library")
	require.NoError(t, os.MkdirAll(libraryPath, 0755))

	thumbDir := filepath.Join(tempDir, "thumbnails")
	require.NoError(t, os.MkdirAll(thumbDir, 0755))
	thumbSvc := services.NewThumbnailService(thumbDir)

	mediaCfg := config.MediaConfig{
		VideoPath:     filepath.Join(libraryPath, "video"),
		AudioPath:     filepath.Join(libraryPath, "audio"),
		ImagePath:     filepath.Join(libraryPath, "images"),
		ThumbnailPath: thumbDir,
	}
	quarantinePath := filepath.Join(tempDir, "originals")
	require.NoError(t, os.MkdirAll(quarantinePath, 0755))
	storageCfg := config.StorageConfig{
		OriginalsDir: quarantinePath,
		TempDir:      filepath.Join(tempDir, "tmp"),
	}
	require.NoError(t, os.MkdirAll(storageCfg.TempDir, 0755))
	queue := services.NewUploadQueue(context.Background(), mediaRepo, repository.NewUploadTaskRepository(db), thumbSvc, workers, queueLimit)
	stub := &stubTranscodeQueue{}
	cfg := handlers.UploadConfig{
		MaxFileSize: 10 * 1024 * 1024,
	}
	handler := handlers.NewUploadHandler(mediaRepo, queue, stub, mediaCfg, storageCfg, cfg)

	app := fiber.New(fiber.Config{
		BodyLimit: 5 * 1024 * 1024,
	})
	app.Post("/api/media/upload", handler.Upload)
	app.Get("/api/media/uploads/:id", handler.UploadStatus)
	app.Delete("/api/media/uploads/:id", handler.CancelUpload)

	return app, mediaRepo, libraryPath, stub, quarantinePath, func() {
		queue.Stop()
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}
}

// stubTranscodeQueue — стаб очереди нормализации для тестов хендлера:
// фиксирует вызовы, файлы не трогает (кроме Cancel, который убирает
// исходник — как настоящая очередь).
type stubTranscodeQueue struct {
	mu        sync.Mutex
	enqueued  []transcodeEnqueueCall
	byID      map[uint64]string
	nextID    uint64
	status    services.TranscodeJobStatus
	statusOK  bool
	cancelErr error
	cancelled []uint64
	retryErr  error
	spaceErr  error
}

type transcodeEnqueueCall struct {
	sourcePath string
	filename   string
}

func (s *stubTranscodeQueue) Enqueue(sourcePath, filename string) (uint64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.nextID++
	if s.byID == nil {
		s.byID = make(map[uint64]string)
	}
	s.byID[s.nextID] = sourcePath
	s.enqueued = append(s.enqueued, transcodeEnqueueCall{sourcePath: sourcePath, filename: filename})
	return s.nextID, nil
}

func (s *stubTranscodeQueue) Get(id uint64) (services.TranscodeJobStatus, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = id
	return s.status, s.statusOK
}

func (s *stubTranscodeQueue) Cancel(id uint64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cancelErr != nil {
		return s.cancelErr
	}
	s.cancelled = append(s.cancelled, id)
	// Эмулируем настоящую отмену: исходник задания удаляется.
	if src := s.byID[id]; src != "" {
		_ = os.Remove(src)
	}
	return nil
}

func (s *stubTranscodeQueue) CancelBySource(string) error { return nil }

func (s *stubTranscodeQueue) Retry(uint64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.retryErr
}

func (s *stubTranscodeQueue) EnsureSpaceForUpload(int64) error { return s.spaceErr }

func (s *stubTranscodeQueue) OriginalsStatus() ([]services.OriginalInfo, error) {
	return nil, nil
}

func (s *stubTranscodeQueue) enqueuedCount() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.enqueued)
}

func createMultipartForm(t *testing.T, filename string, content []byte, mediaType string) (*bytes.Buffer, string) {
	t.Helper()

	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)

	err := writer.WriteField("media_type", mediaType)
	require.NoError(t, err)

	part, err := writer.CreateFormFile("file", filename)
	require.NoError(t, err)
	_, err = part.Write(content)
	require.NoError(t, err)

	err = writer.Close()
	require.NoError(t, err)

	return body, writer.FormDataContentType()
}

// uploadFile отправляет POST /upload и возвращает ответ.
func uploadFile(t *testing.T, app *fiber.App, filename string, content []byte, mediaType string) *http.Response {
	t.Helper()
	body, contentType := createMultipartForm(t, filename, content, mediaType)
	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)
	resp, err := app.Test(req)
	require.NoError(t, err)
	return resp
}

// jobIDFromResponse извлекает job_id из ответа POST /upload.
func jobIDFromResponse(t *testing.T, resp *http.Response) int64 {
	t.Helper()
	var out struct {
		JobID int64 `json:"job_id"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	return out.JobID
}

// uploadAndParseJob загружает файл и возвращает (job_id, job_type).
// job_type (upload/transcode) говорит клиенту, какой эндпоинт опрашивать:
// числовые ID пространств могут пересекаться.
func uploadAndParseJob(t *testing.T, app *fiber.App, filename string, content []byte, mediaType string) (int64, string) {
	t.Helper()
	resp := uploadFile(t, app, filename, content, mediaType)
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	var out struct {
		JobID   int64  `json:"job_id"`
		JobType string `json:"job_type"`
	}
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	return out.JobID, out.JobType
}

// uploadJobStatus делает GET /uploads/:id.
func uploadJobStatus(t *testing.T, app *fiber.App, jobID int64) (*http.Response, map[string]interface{}) {
	t.Helper()
	resp, err := app.Test(httptest.NewRequest("GET", fmt.Sprintf("/api/media/uploads/%d", jobID), nil))
	require.NoError(t, err)
	var out map[string]interface{}
	if resp.StatusCode == fiber.StatusOK {
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
	}
	return resp, out
}

// waitForUploadJob поллит статус задания до терминального (done/error)
// или до истечения таймаута.
func waitForUploadJob(t *testing.T, app *fiber.App, jobID int64) (map[string]interface{}, *http.Response) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	var resp *http.Response
	var out map[string]interface{}
	for time.Now().Before(deadline) {
		resp, out = uploadJobStatus(t, app, jobID)
		require.Equal(t, fiber.StatusOK, resp.StatusCode)
		status, _ := out["status"].(string)
		if status == services.UploadJobDone || status == services.UploadJobError || status == services.UploadJobDuplicate {
			return out, resp
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("upload job %d did not reach terminal state within timeout", jobID)
	return nil, nil
}

// countFilesInDir возвращает число файлов в каталоге (или 0, если нет).
func countFilesInDir(t *testing.T, dir string) int {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return 0
		}
		t.Fatalf("read dir %s: %v", dir, err)
	}
	return len(entries)
}

// testMemeImage рисует детерминированную картинку и кодирует её в png
// или jpeg: один и тот же кадр в разных форматах нужен для проверки
// pHash-дубля (точный хэш при этом разный).
func testMemeImage(t *testing.T, format string) []byte {
	t.Helper()

	img := image.NewRGBA(image.Rect(0, 0, 64, 64))
	for y := range 64 {
		for x := range 64 {
			img.Set(x, y, color.RGBA{R: uint8(x * 4), G: uint8(y * 4), B: 128, A: 255})
		}
	}
	for y := range 16 {
		for x := range 16 {
			img.Set(x, y, color.RGBA{R: 255, A: 255})
		}
	}

	var buf bytes.Buffer
	switch format {
	case "png":
		require.NoError(t, png.Encode(&buf, img))
	case "jpeg":
		require.NoError(t, jpeg.Encode(&buf, img, nil))
	default:
		t.Fatalf("unsupported image format: %s", format)
	}
	return buf.Bytes()
}

func TestUploadSuccess(t *testing.T) {
	app, mediaRepo, _, stub, quarantinePath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Видео уходит в карантин и ставится в очередь нормализации
	// (настоящий транскод — на уровне сервисов с фейковым раннером).
	resp := uploadFile(t, app, "test.mp4", []byte("test file content"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)
	require.Greater(t, jobID, int64(0))
	require.Equal(t, 1, stub.enqueuedCount())

	// Файл в карантине, в библиотеке и БД пока ничего нет.
	_, err := os.Stat(filepath.Join(quarantinePath, "test.mp4"))
	require.NoError(t, err)
	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	assert.Empty(t, mediaList)

	// Статус задания виден через fallback /uploads/:id.
	stub.status = services.TranscodeJobStatus{Status: services.TranscodeTaskQueued}
	stub.statusOK = true
	statusResp, out := uploadJobStatus(t, app, jobID)
	require.Equal(t, fiber.StatusOK, statusResp.StatusCode)
	assert.Equal(t, services.TranscodeTaskQueued, out["status"])
}

func TestUploadStatusNotFound(t *testing.T) {
	app, _, _, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/uploads/999", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/uploads/not-a-number", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	// Нулевой ID — тоже 400 (автоинкремент начинается с 1), а не 404.
	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/uploads/0", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("DELETE", "/api/media/uploads/0", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestUploadMissingFile(t *testing.T) {
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	require.NoError(t, writer.WriteField("media_type", string(models.MediaTypeVideo)))
	require.NoError(t, writer.Close())

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	// Задание не создано, файлов не появилось.
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadInvalidMediaType(t *testing.T) {
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp := uploadFile(t, app, "test.mp4", []byte("test file content"), "garbage")
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadInvalidFilename(t *testing.T) {
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Имя с backslash-разделителем: fasthttp вырезает "/..", но backslash
	// проходит до SanitizeFilename, который отклоняет его — без создания
	// задания.
	resp := uploadFile(t, app, "..\\evil.mp4", []byte("x"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadFileTooLarge(t *testing.T) {
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	fileContent := make([]byte, 7*1024*1024)
	body, contentType := createMultipartForm(t, "large.mp4", fileContent, string(models.MediaTypeVideo))

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", contentType)

	_, err := app.Test(req, 10000)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "body size exceeds the given limit")
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadDuplicateFile(t *testing.T) {
	app, mediaRepo, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	fileContent := []byte("duplicate content")

	first := uploadFile(t, app, "dup.mp3", fileContent, string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)
	firstID := jobIDFromResponse(t, first)

	firstOut, _ := waitForUploadJob(t, app, firstID)
	assert.Equal(t, services.UploadJobDone, firstOut["status"])

	// Тот же контент — тот же хэш: второе задание падает с error,
	// а не создаёт запись. Статус об ошибке без утечки путей.
	second := uploadFile(t, app, "dup2.mp3", fileContent, string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, second.StatusCode)
	secondID := jobIDFromResponse(t, second)

	secondOut, _ := waitForUploadJob(t, app, secondID)
	assert.Equal(t, services.UploadJobError, secondOut["status"])
	assert.Equal(t, "File already exists", secondOut["error"])
	require.NotContains(t, fmt.Sprint(secondOut), libraryPath)

	// Файл дубликата удалён с диска, запись одна.
	_, err := os.Stat(filepath.Join(libraryPath, "audio", "dup2.mp3"))
	require.True(t, os.IsNotExist(err))
	_, err = os.Stat(filepath.Join(libraryPath, "audio", "dup.mp3"))
	require.NoError(t, err)

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
}

func TestUploadCancel(t *testing.T) {
	// workers=0: задание гарантированно остаётся queued — отмена
	// детерминированна. Видео отменяется через fallback транскода.
	app, _, _, _, quarantinePath, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	resp := uploadFile(t, app, "cancel.mp4", []byte("to be cancelled"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	filePath := filepath.Join(quarantinePath, "cancel.mp4")
	_, err := os.Stat(filePath)
	require.NoError(t, err)

	resp, err = app.Test(httptest.NewRequest("DELETE", fmt.Sprintf("/api/media/uploads/%d", jobID), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)

	// Файл удалён, задание исчезло.
	_, err = os.Stat(filePath)
	require.True(t, os.IsNotExist(err), "cancelled upload file must be removed")

	statusResp, err := app.Test(httptest.NewRequest("GET", fmt.Sprintf("/api/media/uploads/%d", jobID), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, statusResp.StatusCode)
}

func TestUploadCancelDoneConflict(t *testing.T) {
	app, _, _, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp := uploadFile(t, app, "done.mp3", []byte("done content"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	waitForUploadJob(t, app, jobID)

	// Done-задание отменить нельзя → 409.
	resp, err := app.Test(httptest.NewRequest("DELETE", fmt.Sprintf("/api/media/uploads/%d", jobID), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestUploadCancelNotFound(t *testing.T) {
	app, _, _, stub, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()
	stub.cancelErr = services.ErrTranscodeJobNotFound

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/uploads/4242", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestUploadCancelConflict(t *testing.T) {
	// Гонка проиграна (транскод-очередь вернула конфликт) — 409, а не 500.
	app, _, _, stub, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()
	stub.cancelErr = services.ErrTranscodeConflict

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/uploads/4242", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestUploadQueueFull(t *testing.T) {
	// Лимит очереди 1, воркеры не обрабатывают: второе задание получает 429.
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 0, 1)
	defer cleanup()

	first := uploadFile(t, app, "one.mp3", []byte("one"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)

	second := uploadFile(t, app, "two.mp3", []byte("two"), string(models.MediaTypeAudio))
	assert.Equal(t, fiber.StatusTooManyRequests, second.StatusCode)
	body, err := io.ReadAll(second.Body)
	require.NoError(t, err)
	assert.Contains(t, string(body), "Upload queue is full")

	// Файл переполненной загрузки удалён: на диске только первый файл.
	_, err = os.Stat(filepath.Join(libraryPath, "audio", "one.mp3"))
	require.NoError(t, err)
	_, err = os.Stat(filepath.Join(libraryPath, "audio", "two.mp3"))
	require.True(t, os.IsNotExist(err), "rejected upload file must be removed")
}

func TestUploadMediaTypeFromForm(t *testing.T) {
	app, mediaRepo, _, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// media_type=audio задан явно: в Type записи сохраняется именно он,
	// а не определение по расширению (.mp4 → video).
	resp := uploadFile(t, app, "song.mp4", []byte("audio content"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)
	out, _ := waitForUploadJob(t, app, jobID)
	assert.Equal(t, services.UploadJobDone, out["status"])

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	assert.Equal(t, models.MediaTypeAudio, mediaList[0].Type)
}

func TestUploadMediaTypeByExtension(t *testing.T) {
	app, mediaRepo, _, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// media_type не задан: тип определяется по расширению (.mp3 → audio).
	body := new(bytes.Buffer)
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", "song.mp3")
	require.NoError(t, err)
	_, err = part.Write([]byte("audio content"))
	require.NoError(t, err)
	require.NoError(t, writer.Close())

	req := httptest.NewRequest("POST", "/api/media/upload", body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)
	out, _ := waitForUploadJob(t, app, jobID)
	assert.Equal(t, services.UploadJobDone, out["status"])

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	assert.Equal(t, models.MediaTypeAudio, mediaList[0].Type)
}

func TestUploadErrorResponseHidesPaths(t *testing.T) {
	app, _, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Битый файл не сломает задание: обработка не падает в панику даже
	// на невалидном контенте — задание доходит до терминального статуса,
	// а ответ не содержит путей ФС.
	resp := uploadFile(t, app, "bad.mp3", []byte("garbage"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	out, _ := waitForUploadJob(t, app, jobID)
	assert.Equal(t, services.UploadJobDone, out["status"])
	require.NotContains(t, fmt.Sprint(out), libraryPath)
}

func TestUploadImageGoesToImagePath(t *testing.T) {
	cases := []struct {
		name      string
		filename  string
		mediaType string
	}{
		{name: "explicit", filename: "meme.png", mediaType: string(models.MediaTypeImage)},
		{name: "by extension", filename: "meme.webp", mediaType: ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			app, mediaRepo, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
			defer cleanup()

			resp := uploadFile(t, app, tc.filename, []byte("image content"), tc.mediaType)
			require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
			jobID := jobIDFromResponse(t, resp)
			out, _ := waitForUploadJob(t, app, jobID)
			assert.Equal(t, services.UploadJobDone, out["status"])

			// Картинка кладётся в image_path, а не в video/audio.
			_, err := os.Stat(filepath.Join(libraryPath, "images", tc.filename))
			require.NoError(t, err)

			mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
			require.NoError(t, err)
			require.Len(t, mediaList, 1)
			assert.Equal(t, models.MediaTypeImage, mediaList[0].Type)
		})
	}
}

func TestUploadSimilarImageReturnsDuplicate(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg не установлен")
	}

	app, mediaRepo, libraryPath, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Первый мем — PNG, второй — тот же кадр в JPEG: точные хэши разные,
	// pHash должен совпасть в пределах порога.
	resp := uploadFile(t, app, "meme.png", testMemeImage(t, "png"), string(models.MediaTypeImage))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	firstJob := jobIDFromResponse(t, resp)
	first, _ := waitForUploadJob(t, app, firstJob)
	require.Equal(t, services.UploadJobDone, first["status"])

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	firstID := mediaList[0].ID

	resp = uploadFile(t, app, "meme-copy.jpg", testMemeImage(t, "jpeg"), string(models.MediaTypeImage))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	secondJob := jobIDFromResponse(t, resp)
	second, _ := waitForUploadJob(t, app, secondJob)

	assert.Equal(t, services.UploadJobDuplicate, second["status"])
	duplicate, ok := second["duplicate"].(map[string]interface{})
	require.True(t, ok, "status duplicate должен нести похожий мем")
	assert.Equal(t, float64(firstID), duplicate["id"])
	assert.Equal(t, "meme", duplicate["title"])

	// Файл дубля удалён, в библиотеке остался один мем.
	_, err = os.Stat(filepath.Join(libraryPath, "images", "meme-copy.jpg"))
	assert.True(t, os.IsNotExist(err))
	mediaList, _, err = mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	assert.Len(t, mediaList, 1)
}

func TestUploadVideoGoesToQuarantine(t *testing.T) {
	app, _, libraryPath, stub, quarantinePath, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	resp := uploadFile(t, app, "movie.mkv", []byte("video bytes"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)

	// Файл в карантине с исходным именем, в библиотеке пусто.
	_, err := os.Stat(filepath.Join(quarantinePath, "movie.mkv"))
	require.NoError(t, err)
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
	require.Equal(t, 1, stub.enqueuedCount())
}

func TestUploadJobTypeContract(t *testing.T) {
	app, _, _, _, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	_, videoType := uploadAndParseJob(t, app, "movie.mkv", []byte("video"), string(models.MediaTypeVideo))
	assert.Equal(t, "transcode", videoType)
	_, audioType := uploadAndParseJob(t, app, "song.mp3", []byte("audio"), string(models.MediaTypeAudio))
	assert.Equal(t, "upload", audioType)
}

func TestUploadVideoParallelSameName(t *testing.T) {
	// Десять параллельных загрузок с одним именем: O_EXCL гарантирует,
	// что ни одна не перезапишет другую — все приняты под разными именами.
	app, _, _, stub, quarantinePath, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	const parallel = 10
	var wg sync.WaitGroup
	ids := make([]int64, parallel)
	for i := 0; i < parallel; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			body, contentType := createMultipartForm(t, "same.mp4", []byte{byte(i), 1, 2, 3}, string(models.MediaTypeVideo))
			req := httptest.NewRequest("POST", "/api/media/upload", body)
			req.Header.Set("Content-Type", contentType)
			resp, err := app.Test(req)
			require.NoError(t, err)
			require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
			var out struct {
				JobID int64 `json:"job_id"`
			}
			require.NoError(t, json.NewDecoder(resp.Body).Decode(&out))
			ids[i] = out.JobID
		}(i)
	}
	wg.Wait()

	// Все ID различны, файлов на диске ровно столько же.
	seen := make(map[int64]bool)
	for _, id := range ids {
		require.Greater(t, id, int64(0))
		require.False(t, seen[id], "duplicate job id")
		seen[id] = true
	}
	entries, err := os.ReadDir(quarantinePath)
	require.NoError(t, err)
	assert.Len(t, entries, parallel)
	assert.Equal(t, parallel, stub.enqueuedCount())
}

func TestUploadVideoSameNameUnique(t *testing.T) {
	app, _, _, stub, quarantinePath, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	first := uploadFile(t, app, "same.mp4", []byte("one"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)
	second := uploadFile(t, app, "same.mp4", []byte("two"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, second.StatusCode)

	// Никаких 409: второе имя уникализировано, оба задания в очереди.
	_, err := os.Stat(filepath.Join(quarantinePath, "same.mp4"))
	require.NoError(t, err)
	_, err = os.Stat(filepath.Join(quarantinePath, "same (2).mp4"))
	require.NoError(t, err)
	require.Equal(t, 2, stub.enqueuedCount())
}

func TestUploadVideoNoSpace(t *testing.T) {
	app, _, _, stub, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()
	stub.spaceErr = services.ErrInsufficientSpace

	resp := uploadFile(t, app, "big.mp4", []byte("data"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusInsufficientStorage, resp.StatusCode)
	assert.Equal(t, 0, stub.enqueuedCount())
}
