package services

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
)

// TestRemoveMediaForPathMovesToTrash: watcher при исчезновении файла
// отправляет запись в корзину, а не удаляет её навсегда. Превью остаётся
// на диске — оно нужно для восстановления, окончательно чистит purge.
func TestRemoveMediaForPathMovesToTrash(t *testing.T) {
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	repo := repository.NewMediaRepository(db)
	thumbDir := t.TempDir()
	scanner := NewScannerService(repo, &config.Config{
		Media: config.MediaConfig{ThumbnailPath: thumbDir},
	})

	path := filepath.Join(t.TempDir(), "gone.mp4")
	media := &models.Media{
		Title:    "Gone",
		Filename: "gone.mp4",
		Type:     models.MediaTypeVideo,
		FilePath: path,
		FileSize: 100,
	}
	require.NoError(t, repo.Create(context.Background(), media))

	thumbPath := scanner.thumbService.GetPath(media.ID)
	require.NoError(t, os.WriteFile(thumbPath, []byte("thumb"), 0644))

	scanner.removeMediaForPath(context.Background(), path)

	trashed, err := repo.FindByPath(context.Background(), path)
	require.NoError(t, err)
	assert.True(t, trashed.DeletedAt.Valid, "запись должна уйти в корзину")
	assert.True(t, trashed.AutoTrashed, "watcher помечает запись как AutoTrashed")
	_, err = repo.FindByID(context.Background(), media.ID)
	assert.Error(t, err, "живой список не должен видеть пропавший файл")
	assert.FileExists(t, thumbPath, "превью нужно для восстановления из корзины")
}
