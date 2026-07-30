package services

import (
	"context"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/repository"
)

func setupStreamer(t *testing.T, libs []models.MediaLibrary) *StreamerService {
	t.Helper()
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	repo := repository.NewLibraryRepository(db)
	ctx := context.Background()
	for i := range libs {
		require.NoError(t, repo.Create(ctx, &libs[i]))
	}
	return NewStreamerService(repo)
}

func TestIsPathAllowed(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "video")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	realFile := filepath.Join(libDir, "movie.mp4")
	require.NoError(t, os.WriteFile(realFile, []byte("x"), 0644))

	outsideFile := filepath.Join(dir, "secret.txt")
	require.NoError(t, os.WriteFile(outsideFile, []byte("x"), 0644))

	s := setupStreamer(t, []models.MediaLibrary{
		{Name: "Video", Path: libDir, Type: "video", Enabled: true},
	})
	ctx := context.Background()

	allowed, err := s.IsPathAllowed(ctx, realFile)
	require.NoError(t, err)
	assert.True(t, allowed, "file inside enabled library must be allowed")

	allowed, err = s.IsPathAllowed(ctx, outsideFile)
	require.NoError(t, err)
	assert.False(t, allowed, "file outside any library must be rejected")

	// Traversal that resolves outside the library.
	allowed, err = s.IsPathAllowed(ctx, filepath.Join(libDir, "..", "secret.txt"))
	require.NoError(t, err)
	assert.False(t, allowed, "traversal outside library must be rejected")

	// Symlink pointing outside the library must be rejected.
	link := filepath.Join(libDir, "evil.mp4")
	if err := os.Symlink(outsideFile, link); err == nil {
		allowed, err = s.IsPathAllowed(ctx, link)
		require.NoError(t, err)
		assert.False(t, allowed, "symlink escaping the library must be rejected")
	}
}

func TestIsPathAllowedDisabledLibrary(t *testing.T) {
	dir := t.TempDir()
	realFile := filepath.Join(dir, "movie.mp4")
	require.NoError(t, os.WriteFile(realFile, []byte("x"), 0644))

	s := setupStreamer(t, []models.MediaLibrary{
		{Name: "Video", Path: dir, Type: "video", Enabled: false},
	})

	allowed, err := s.IsPathAllowed(context.Background(), realFile)
	require.NoError(t, err)
	assert.False(t, allowed, "disabled library must not serve files")
}

func TestParseRangeHeader(t *testing.T) {
	tests := []struct {
		name      string
		header    string
		size      int64
		wantStart int64
		wantEnd   int64
		wantErr   bool
	}{
		{"first bytes", "bytes=0-499", 1000, 0, 499, false},
		{"open end", "bytes=500-", 1000, 500, 999, false},
		{"suffix", "bytes=-100", 1000, 900, 999, false},
		{"suffix larger than file", "bytes=-5000", 1000, 0, 999, false},
		{"single byte", "bytes=0-0", 1000, 0, 0, false},
		{"start beyond size", "bytes=1000-", 1000, 0, 0, true},
		{"end beyond size", "bytes=0-1000", 1000, 0, 0, true},
		{"end before start", "bytes=500-100", 1000, 0, 0, true},
		{"negative start", "bytes=-1-100", 1000, 0, 0, true},
		{"invalid unit", "items=0-100", 1000, 0, 0, true},
		{"garbage", "bytes=", 1000, 0, 0, true},
		{"non-numeric", "bytes=a-b", 1000, 0, 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			start, end, err := parseRangeHeader(tt.header, tt.size)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.wantStart, start)
			assert.Equal(t, tt.wantEnd, end)
		})
	}
}

func TestMimeTypeByExt(t *testing.T) {
	assert.Equal(t, "video/mp4", mimeTypeByExt(".mp4"))
	assert.Equal(t, "video/x-matroska", mimeTypeByExt(".mkv"))
	assert.Equal(t, "audio/mpeg", mimeTypeByExt(".mp3"))
	assert.Equal(t, "audio/flac", mimeTypeByExt(".flac"))
	assert.Equal(t, "audio/ogg", mimeTypeByExt(".ogg"))
	assert.Equal(t, "audio/wav", mimeTypeByExt(".wav"))
	assert.Equal(t, "application/octet-stream", mimeTypeByExt(".xyz"))
}

func TestStream(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "library")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	filePath := filepath.Join(libDir, "test.mp4")
	content := []byte("fake mp4 content")
	require.NoError(t, os.WriteFile(filePath, content, 0644))

	app := fiber.New()
	s := setupStreamer(t, []models.MediaLibrary{
		{Name: "Video", Path: libDir, Type: "video", Enabled: true},
	})

	app.Get("/stream", func(c *fiber.Ctx) error {
		return s.Stream(c, filePath)
	})

	req := httptest.NewRequest("GET", "/stream", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)

	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	assert.Equal(t, content, body)
}

func TestStreamNotFound(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "library")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	app := fiber.New()
	s := setupStreamer(t, []models.MediaLibrary{
		{Name: "Video", Path: libDir, Type: "video", Enabled: true},
	})

	app.Get("/stream", func(c *fiber.Ctx) error {
		return s.Stream(c, filepath.Join(libDir, "nonexistent.mp4"))
	})

	req := httptest.NewRequest("GET", "/stream", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}
