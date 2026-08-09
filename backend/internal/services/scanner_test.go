package services_test

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
