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
)

func setupStreamer(t *testing.T, mediaPaths ...string) *StreamerService {
	t.Helper()
	var paths []config.MediaPath
	for _, p := range mediaPaths {
		paths = append(paths, config.MediaPath{Path: p, Type: models.MediaTypeVideo})
	}
	cfg := &config.Config{Media: config.MediaConfig{}}
	cfg.Media.VideoPath = paths[0].Path
	return NewStreamerService(cfg)
}

func TestIsPathAllowed(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "video")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	realFile := filepath.Join(libDir, "movie.mp4")
	require.NoError(t, os.WriteFile(realFile, []byte("x"), 0644))

	outsideFile := filepath.Join(dir, "secret.txt")
	require.NoError(t, os.WriteFile(outsideFile, []byte("x"), 0644))

	s := setupStreamer(t, libDir)
	ctx := context.Background()

	allowed, err := s.IsPathAllowed(ctx, realFile)
	require.NoError(t, err)
	assert.True(t, allowed, "file inside media path must be allowed")

	allowed, err = s.IsPathAllowed(ctx, outsideFile)
	require.NoError(t, err)
	assert.False(t, allowed, "file outside any media path must be rejected")

	// Traversal that resolves outside the media path.
	allowed, err = s.IsPathAllowed(ctx, filepath.Join(libDir, "..", "secret.txt"))
	require.NoError(t, err)
	assert.False(t, allowed, "traversal outside media path must be rejected")

	// Symlink pointing outside the media path must be rejected.
	link := filepath.Join(libDir, "evil.mp4")
	if err := os.Symlink(outsideFile, link); err == nil {
		allowed, err = s.IsPathAllowed(ctx, link)
		require.NoError(t, err)
		assert.False(t, allowed, "symlink escaping the media path must be rejected")
	}
}

func TestMimeTypeByExt(t *testing.T) {
	assert.Equal(t, "video/mp4", MimeTypeByExt(".mp4"))
	assert.Equal(t, "video/x-matroska", MimeTypeByExt(".mkv"))
	assert.Equal(t, "audio/mpeg", MimeTypeByExt(".mp3"))
	assert.Equal(t, "audio/flac", MimeTypeByExt(".flac"))
	assert.Equal(t, "audio/ogg", MimeTypeByExt(".ogg"))
	assert.Equal(t, "audio/wav", MimeTypeByExt(".wav"))
	assert.Equal(t, "application/octet-stream", MimeTypeByExt(".xyz"))
}

func TestResolveStreamPath(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "library")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	filePath := filepath.Join(libDir, "test.mp4")
	content := []byte("fake mp4 content")
	require.NoError(t, os.WriteFile(filePath, content, 0644))

	outsideFile := filepath.Join(dir, "secret.txt")
	require.NoError(t, os.WriteFile(outsideFile, []byte("x"), 0644))

	s := setupStreamer(t, libDir)
	ctx := context.Background()

	// Файл внутри библиотеки: разрешён, резолвнутый путь совпадает.
	allowed, resolved, err := s.ResolveStreamPath(ctx, filePath)
	require.NoError(t, err)
	assert.True(t, allowed)
	assert.Equal(t, filePath, resolved)

	// Файл вне библиотеки: запрещён.
	allowed, _, err = s.ResolveStreamPath(ctx, outsideFile)
	require.NoError(t, err)
	assert.False(t, allowed)

	// Симлинк из библиотеки наружу: запрещён.
	link := filepath.Join(libDir, "evil.mp4")
	if err := os.Symlink(outsideFile, link); err == nil {
		allowed, _, err = s.ResolveStreamPath(ctx, link)
		require.NoError(t, err)
		assert.False(t, allowed, "symlink escaping the media path must be rejected")
	}
}

func TestResolveStreamPathMissingFile(t *testing.T) {
	dir := t.TempDir()
	libDir := filepath.Join(dir, "library")
	require.NoError(t, os.MkdirAll(libDir, 0755))

	s := setupStreamer(t, libDir)
	ctx := context.Background()

	// Несуществующий файл в библиотеке: EvalSymlinks падает, путь остаётся
	// валидным (файл может появиться до отправки) — решение об ответе
	// принимает хендлер по результату SendFile.
	allowed, resolved, err := s.ResolveStreamPath(ctx, filepath.Join(libDir, "nonexistent.mp4"))
	require.NoError(t, err)
	assert.True(t, allowed)
	assert.Equal(t, filepath.Join(libDir, "nonexistent.mp4"), resolved)
}
