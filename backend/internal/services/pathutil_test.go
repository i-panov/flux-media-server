package services

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidateContentDirs(t *testing.T) {
	good := map[string]string{
		"video":     "/media/video",
		"audio":     "/media/audio",
		"originals": "/media/originals",
		"temp":      "/data/tmp",
	}
	assert.NoError(t, ValidateContentDirs(good))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video":     "/media/video",
		"originals": "/media/video",
	}))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video":     "/media",
		"originals": "/media/originals",
	}))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video": "/media/video",
		"temp":  "",
	}))
}

func TestResolveAllowedFile(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()

	inside := filepath.Join(root, "movie.rus.vtt")
	require.NoError(t, os.WriteFile(inside, []byte("WEBVTT"), 0o644))

	got, ok := ResolveAllowedFile([]string{root}, inside, ".vtt")
	require.True(t, ok)
	assert.Equal(t, inside, got)

	// Другое расширение не пропускаем.
	_, ok = ResolveAllowedFile([]string{root}, inside, ".srt")
	assert.False(t, ok)

	// Симлинк внутри библиотеки, указывающий наружу, не проходит.
	external := filepath.Join(outside, "secret.vtt")
	require.NoError(t, os.WriteFile(external, []byte("WEBVTT"), 0o644))
	link := filepath.Join(root, "link.vtt")
	require.NoError(t, os.Symlink(external, link))
	_, ok = ResolveAllowedFile([]string{root}, link, ".vtt")
	assert.False(t, ok, "симлинк за пределы библиотеки запрещён")

	// Несуществующий файл.
	_, ok = ResolveAllowedFile([]string{root}, filepath.Join(root, "missing.vtt"), ".vtt")
	assert.False(t, ok)
}
