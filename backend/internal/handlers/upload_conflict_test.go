package handlers_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

// Сирота (файл без строки — след отменённой/упавшей загрузки):
// повтор принимается, stale-файл заменяется, а не вечный 409.
func TestUploadOrphanFileReused(t *testing.T) {
	app, _, _, _, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	first := uploadFile(t, app, "orphan.mp3", []byte("data"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, first.StatusCode)

	second := uploadFile(t, app, "orphan.mp3", []byte("data"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusAccepted, second.StatusCode, "сирота не блокирует повтор")
}

// Живая строка + файл: честный 409.
func TestUploadLiveConflict(t *testing.T) {
	app, mediaRepo, libraryPath, _, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	dst := filepath.Join(libraryPath, "audio", "live.mp3")
	require.NoError(t, os.MkdirAll(filepath.Dir(dst), 0755))
	require.NoError(t, os.WriteFile(dst, []byte("data"), 0644))
	require.NoError(t, mediaRepo.Create(context.Background(), &models.Media{
		Title: "Live", Type: models.MediaTypeAudio, FilePath: dst,
	}))

	resp := uploadFile(t, app, "live.mp3", []byte("data"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusConflict, resp.StatusCode)
}

// Trashed-строка + файл: 409 с намёком на корзину (файл её, не трогаем).
func TestUploadTrashConflict(t *testing.T) {
	app, mediaRepo, libraryPath, _, _, cleanup := setupUploadTest(t, 0, 50)
	defer cleanup()

	dst := filepath.Join(libraryPath, "audio", "trashed.mp3")
	require.NoError(t, os.MkdirAll(filepath.Dir(dst), 0755))
	require.NoError(t, os.WriteFile(dst, []byte("data"), 0644))
	m := &models.Media{Title: "Trashed", Type: models.MediaTypeAudio, FilePath: dst}
	require.NoError(t, mediaRepo.Create(context.Background(), m))
	require.NoError(t, mediaRepo.Delete(context.Background(), m.ID))

	resp := uploadFile(t, app, "trashed.mp3", []byte("data"), string(models.MediaTypeAudio))
	require.Equal(t, fiber.StatusConflict, resp.StatusCode)

	// Файл корзины цел — purge/restore работают как раньше.
	_, err := os.Stat(dst)
	require.NoError(t, err)
	_, err = mediaRepo.FindTrashedMedia(context.Background(), m.ID)
	require.NoError(t, err)
}
