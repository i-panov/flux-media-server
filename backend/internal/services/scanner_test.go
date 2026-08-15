package services_test

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupTestDB(t *testing.T) *repository.MediaStore {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)

	err = repository.AutoMigrate(db)
	require.NoError(t, err)

	return repository.NewMediaRepository(db)
}

func TestScannerFFProbeSingleCall(t *testing.T) {
	mediaRepo := setupTestDB(t)

	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")

	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}

	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx := context.Background()
	err = scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo)
	require.NoError(t, err)

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)
	assert.NotEmpty(t, media.FileHash)
}

func TestScannerSweepDeletedMedia(t *testing.T) {
	mediaRepo := setupTestDB(t)

	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")
	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}

	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx := context.Background()
	err = scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo)
	require.NoError(t, err)

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)

	err = os.Remove(testFile)
	require.NoError(t, err)

	err = scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo)
	require.NoError(t, err)

	_, err = mediaRepo.FindByPath(ctx, testFile)
	assert.Error(t, err)
}

// TestScannerSweepDeletedKeysetNoSkips: больше pageSize (200) записей без
// файлов на диске — sweep обязан удалить ВСЕ. Offset-пагинация с удалением
// в цикле сдвигала окно и пропускала записи (регрессия).
func TestScannerSweepDeletedKeysetNoSkips(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	const count = 450 // > pageSize в sweepDeleted (200)
	for i := 0; i < count; i++ {
		media := &models.Media{
			Title:    fmt.Sprintf("m%d", i),
			Filename: fmt.Sprintf("f%d.mp4", i),
			FilePath: filepath.Join(tempDir, fmt.Sprintf("f%d.mp4", i)),
			FileSize: 100,
			Type:     models.MediaTypeVideo,
		}
		require.NoError(t, mediaRepo.Create(ctx, media))
	}

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	require.NoError(t, scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo))

	_, total, err := mediaRepo.FindAll(ctx, nil, 0, 0)
	require.NoError(t, err)
	assert.Zero(t, total, "sweep должен удалить все записи без файлов, без пропусков")
}

// TestScannerContextCancellation: отмена контекста прерывает скан.
func TestScannerContextCancellation(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()

	testFile := filepath.Join(tempDir, "cancel.mp4")
	err := os.WriteFile(testFile, bytes.Repeat([]byte{0x11}, 1024), 0644)
	require.NoError(t, err)

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err = scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo)
	assert.ErrorIs(t, err, context.Canceled)

	// После отмены статус скана должен быть сброшен: повторный скан не
	// должен возвращать ErrScanInProgress.
	err = scanner.ScanPath(context.Background(), tempDir, models.MediaTypeVideo)
	require.NoError(t, err)
}

// TestScannerUpdateKeepsManualEdits: при пересканировании изменённого файла
// ручные правки Title/Year не затираются тегами/именем файла (регрессия).
func TestScannerUpdateKeepsManualEdits(t *testing.T) {
	mediaRepo := setupTestDB(t)
	tempDir := t.TempDir()
	ctx := context.Background()

	testFile := filepath.Join(tempDir, "test.mp4")
	content := bytes.Repeat([]byte{0x42}, 1500*1024)
	require.NoError(t, os.WriteFile(testFile, content, 0644))

	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
			VideoPath:     tempDir,
		},
	}
	scanner := services.NewScannerService(mediaRepo, cfg)

	require.NoError(t, scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo))

	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	oldQuickHash := media.QuickHash

	// Ручная правка пользователя.
	media.Title = "Ручной заголовок"
	media.Year = 1999
	require.NoError(t, mediaRepo.Update(ctx, media))

	// Изменяем содержимое файла (тот же размер — quick hash детектирует
	// по изменению хвоста).
	modified := make([]byte, len(content))
	copy(modified, content)
	modified[len(modified)-1024] = 0x99
	require.NoError(t, os.WriteFile(testFile, modified, 0644))

	require.NoError(t, scanner.ScanPath(ctx, tempDir, models.MediaTypeVideo))

	after, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, "Ручной заголовок", after.Title, "ручная правка Title не должна затираться")
	assert.Equal(t, 1999, after.Year, "ручная правка Year не должна затираться")
	assert.NotEqual(t, oldQuickHash, after.QuickHash, "quick hash изменившегося файла должен обновиться")
}
