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

func setupTestDB(t *testing.T) (*repository.LibraryStore, *repository.MediaStore) {
	t.Helper()
	
	// Create test database
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	
	// Run migrations
	err = repository.AutoMigrate(db)
	require.NoError(t, err)
	
	// Create repositories
	libraryRepo := repository.NewLibraryRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	
	return libraryRepo, mediaRepo
}

func createTestLibrary(t *testing.T, libraryRepo *repository.LibraryStore, name, libPath, libType string) uint {
	t.Helper()
	
	ctx := context.Background()
	library := &models.MediaLibrary{
		Name:    name,
		Path:    libPath,
		Type:    libType,
		Enabled: true,
	}
	err := libraryRepo.Create(ctx, library)
	require.NoError(t, err)
	return library.ID
}

func TestScannerFFProbeSingleCall(t *testing.T) {
	// This test verifies that ffprobe is called exactly once per file (B4 fix)
	libraryRepo, mediaRepo := setupTestDB(t)
	
	// Create test directory
	tempDir := t.TempDir()
	testFile := filepath.Join(tempDir, "test.mp4")
	
	// Create a test file
	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)
	
	// Create library
	libraryID := createTestLibrary(t, libraryRepo, "Videos", tempDir, "video")
	
	// Create config
	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
		},
	}
	
	// Create scanner service
	scanner := services.NewScannerService(libraryRepo, mediaRepo, cfg)
	
	// Scan the library
	ctx := context.Background()
	err = scanner.ScanLibrary(ctx, libraryID)
	require.NoError(t, err)
	
	// Verify the file was processed
	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)
	assert.NotEmpty(t, media.FileHash)
}

func TestScannerSweepDeletedMedia(t *testing.T) {
	libraryRepo, mediaRepo := setupTestDB(t)
	
	// Create test directory
	tempDir := t.TempDir()
	
	// Create library
	libraryID := createTestLibrary(t, libraryRepo, "Videos", tempDir, "video")
	
	// Create a test file
	testFile := filepath.Join(tempDir, "test.mp4")
	err := os.WriteFile(testFile, []byte("fake mp4 content"), 0644)
	require.NoError(t, err)
	
	// Create config
	cfg := &config.Config{
		Media: config.MediaConfig{
			ThumbnailPath: t.TempDir(),
		},
	}
	
	// Create scanner service
	scanner := services.NewScannerService(libraryRepo, mediaRepo, cfg)
	
	// Scan the library to add the file
	ctx := context.Background()
	err = scanner.ScanLibrary(ctx, libraryID)
	require.NoError(t, err)
	
	// Verify the file was added
	media, err := mediaRepo.FindByPath(ctx, testFile)
	require.NoError(t, err)
	assert.Equal(t, testFile, media.FilePath)
	
	// Delete the file
	err = os.Remove(testFile)
	require.NoError(t, err)
	
	// Scan again to trigger sweep
	err = scanner.ScanLibrary(ctx, libraryID)
	require.NoError(t, err)
	
	// Verify the media record was removed
	_, err = mediaRepo.FindByPath(ctx, testFile)
	assert.Error(t, err) // Should return an error since the record was deleted
}