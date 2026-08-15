package handlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
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
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

// setupUploadTest создаёт приложение с очередью обработки загрузок.
// workers=0 останавливает обработку — задания остаются в статусе queued
// (нужно для тестов отмены и переполнения очереди).
func setupUploadTest(t *testing.T, workers, queueLimit int) (*fiber.App, repository.MediaRepository, string, func()) {
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
		ThumbnailPath: thumbDir,
	}
	queue := services.NewUploadQueue(context.Background(), mediaRepo, thumbSvc, workers, queueLimit)
	cfg := handlers.UploadConfig{
		MaxFileSize: 10 * 1024 * 1024,
	}
	handler := handlers.NewUploadHandler(mediaRepo, queue, mediaCfg, cfg)

	app := fiber.New(fiber.Config{
		BodyLimit: 5 * 1024 * 1024,
	})
	app.Post("/api/media/upload", handler.Upload)
	app.Get("/api/media/uploads/:id", handler.UploadStatus)
	app.Delete("/api/media/uploads/:id", handler.CancelUpload)

	return app, mediaRepo, libraryPath, func() {
		queue.Stop()
		sqlDB, _ := db.DB()
		sqlDB.Close()
	}
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
		if status == services.UploadJobDone || status == services.UploadJobError {
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

func TestUploadSuccess(t *testing.T) {
	app, mediaRepo, libraryPath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp := uploadFile(t, app, "test.mp4", []byte("test file content"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)
	require.Greater(t, jobID, int64(0))

	out, _ := waitForUploadJob(t, app, jobID)
	assert.Equal(t, services.UploadJobDone, out["status"])

	// done: media-объект в ответе и запись в БД.
	mediaObj, ok := out["media"].(map[string]interface{})
	require.True(t, ok, "done job must include media object")
	assert.NotEqual(t, float64(0), mediaObj["id"])
	assert.Equal(t, "test.mp4", mediaObj["filename"])

	// Файл сохранён на диске.
	_, err := os.Stat(filepath.Join(libraryPath, "video", "test.mp4"))
	require.NoError(t, err)

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
	assert.Equal(t, models.MediaTypeVideo, mediaList[0].Type)
	assert.NotEmpty(t, mediaList[0].FileHash)
}

func TestUploadStatusNotFound(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp, err := app.Test(httptest.NewRequest("GET", "/api/media/uploads/999", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)

	resp, err = app.Test(httptest.NewRequest("GET", "/api/media/uploads/not-a-number", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
}

func TestUploadMissingFile(t *testing.T) {
	app, _, libraryPath, cleanup := setupUploadTest(t, 2, 50)
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
	app, _, libraryPath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp := uploadFile(t, app, "test.mp4", []byte("test file content"), "garbage")
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadInvalidFilename(t *testing.T) {
	app, _, libraryPath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Имя с backslash-разделителем: fasthttp вырезает "/..", но backslash
	// проходит до SanitizeFilename, который отклоняет его — без создания
	// задания.
	resp := uploadFile(t, app, "..\\evil.mp4", []byte("x"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)
	assert.Equal(t, 0, countFilesInDir(t, filepath.Join(libraryPath, "video")))
}

func TestUploadFileTooLarge(t *testing.T) {
	app, _, libraryPath, cleanup := setupUploadTest(t, 2, 50)
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
	app, mediaRepo, libraryPath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	fileContent := []byte("duplicate content")

	first := uploadFile(t, app, "dup.mp4", fileContent, string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)
	firstID := jobIDFromResponse(t, first)

	firstOut, _ := waitForUploadJob(t, app, firstID)
	assert.Equal(t, services.UploadJobDone, firstOut["status"])

	// Тот же контент — тот же хэш: второе задание падает с error,
	// а не создаёт запись. Статус об ошибке без утечки путей.
	second := uploadFile(t, app, "dup2.mp4", fileContent, string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, second.StatusCode)
	secondID := jobIDFromResponse(t, second)

	secondOut, _ := waitForUploadJob(t, app, secondID)
	assert.Equal(t, services.UploadJobError, secondOut["status"])
	assert.Equal(t, "File already exists", secondOut["error"])
	require.NotContains(t, fmt.Sprint(secondOut), libraryPath)

	// Файл дубликата удалён с диска, запись одна.
	_, err := os.Stat(filepath.Join(libraryPath, "video", "dup2.mp4"))
	require.True(t, os.IsNotExist(err))
	_, err = os.Stat(filepath.Join(libraryPath, "video", "dup.mp4"))
	require.NoError(t, err)

	mediaList, _, err := mediaRepo.FindAll(context.Background(), repository.MediaFilters{}, 10, 0)
	require.NoError(t, err)
	require.Len(t, mediaList, 1)
}

func TestUploadCancel(t *testing.T) {
	// workers=0: задание гарантированно остаётся queued — отмена
	// детерминированна.
	app, _, libraryPath, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	resp := uploadFile(t, app, "cancel.mp4", []byte("to be cancelled"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	filePath := filepath.Join(libraryPath, "video", "cancel.mp4")
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
	app, _, _, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	resp := uploadFile(t, app, "done.mp4", []byte("done content"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	waitForUploadJob(t, app, jobID)

	// Done-задание отменить нельзя → 409.
	resp, err := app.Test(httptest.NewRequest("DELETE", fmt.Sprintf("/api/media/uploads/%d", jobID), nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

func TestUploadCancelNotFound(t *testing.T) {
	app, _, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/media/uploads/4242", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestUploadQueueFull(t *testing.T) {
	// Лимит очереди 1, воркеры не обрабатывают: второе задание получает 429.
	app, _, libraryPath, cleanup := setupUploadTest(t, 0, 1)
	defer cleanup()

	first := uploadFile(t, app, "one.mp4", []byte("one"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)

	second := uploadFile(t, app, "two.mp4", []byte("two"), string(models.MediaTypeVideo))
	assert.Equal(t, fiber.StatusTooManyRequests, second.StatusCode)
	body, err := io.ReadAll(second.Body)
	require.NoError(t, err)
	assert.Contains(t, string(body), "Upload queue is full")

	// Файл переполненной загрузки удалён: на диске только первый файл.
	_, err = os.Stat(filepath.Join(libraryPath, "video", "one.mp4"))
	require.NoError(t, err)
	_, err = os.Stat(filepath.Join(libraryPath, "video", "two.mp4"))
	require.True(t, os.IsNotExist(err), "rejected upload file must be removed")
}

func TestUploadMediaTypeFromForm(t *testing.T) {
	app, mediaRepo, _, cleanup := setupUploadTest(t, 2, 50)
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
	app, mediaRepo, _, cleanup := setupUploadTest(t, 2, 50)
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
	app, _, libraryPath, cleanup := setupUploadTest(t, 2, 50)
	defer cleanup()

	// Битый файл не сломает задание: обработка не падает в панику даже
	// на невалидном контенте — задание доходит до терминального статуса.
	resp := uploadFile(t, app, "bad.mp4", []byte("garbage"), string(models.MediaTypeVideo))
	require.Equal(t, fiber.StatusAccepted, resp.StatusCode)
	jobID := jobIDFromResponse(t, resp)

	out, _ := waitForUploadJob(t, app, jobID)
	status, _ := out["status"].(string)
	if status == services.UploadJobError {
		// Сообщение об ошибке не должно содержать путей ФС.
		require.NotContains(t, strings.ToLower(fmt.Sprint(out["error"])), "tmp")
		require.NotContains(t, fmt.Sprint(out["error"]), libraryPath)
	}
}
