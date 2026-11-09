package services_test

import (
	"context"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"flux/internal/services"
)

// map-превью мемов: 512 px по длинной стороне, JPEG, без апскейла.
func TestThumbnailService_GenerateImage(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg не установлен")
	}

	cases := []struct {
		name       string
		width      int
		height     int
		wantWidth  int
		wantHeight int
	}{
		{name: "large", width: 600, height: 300, wantWidth: 512, wantHeight: 256},
		{name: "small", width: 100, height: 80, wantWidth: 100, wantHeight: 80},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			src := filepath.Join(dir, "meme.png")
			file, err := os.Create(src)
			require.NoError(t, err)
			img := image.NewRGBA(image.Rect(0, 0, tc.width, tc.height))
			for y := range tc.height {
				for x := range tc.width {
					img.Set(x, y, color.RGBA{R: 20, G: 120, B: 200, A: 255})
				}
			}
			require.NoError(t, png.Encode(file, img))
			require.NoError(t, file.Close())

			svc := services.NewThumbnailService(filepath.Join(dir, "thumbs"))
			out := svc.GenerateWithContext(context.Background(), 42, src)
			require.NotEmpty(t, out)
			assert.Equal(t, svc.GetPath(42), out)

			thumb, err := os.Open(out)
			require.NoError(t, err)
			defer thumb.Close()
			cfg, err := jpeg.DecodeConfig(thumb)
			require.NoError(t, err)
			assert.Equal(t, tc.wantWidth, cfg.Width)
			assert.Equal(t, tc.wantHeight, cfg.Height)
		})
	}
}

// TestGenerateImageKeepsOldThumbOnFFmpegFailure: ffmpeg пишет частичный
// файл и падает — старое превью должно остаться нетронутым, а не быть
// перезаписано мусором под боевым именем.
func TestGenerateImageKeepsOldThumbOnFFmpegFailure(t *testing.T) {
	dir := t.TempDir()
	scriptDir := t.TempDir()
	script := filepath.Join(scriptDir, "ffmpeg")
	require.NoError(t, os.WriteFile(script, []byte("#!/bin/sh\nfor last; do :; done\nprintf garbage > \"$last\"\nexit 1\n"), 0o755))
	t.Setenv("PATH", scriptDir+string(os.PathListSeparator)+os.Getenv("PATH"))

	thumb := services.NewThumbnailService(dir)
	oldPath := thumb.GetPath(7)
	const oldContent = "old thumbnail"
	require.NoError(t, os.WriteFile(oldPath, []byte(oldContent), 0644))

	src := filepath.Join(t.TempDir(), "pic.jpg")
	require.NoError(t, os.WriteFile(src, []byte("not a real jpeg"), 0644))

	require.Equal(t, "", thumb.GenerateWithContext(context.Background(), 7, src))
	got, err := os.ReadFile(oldPath)
	require.NoError(t, err)
	assert.Equal(t, oldContent, string(got))

	entries, err := os.ReadDir(dir)
	require.NoError(t, err)
	assert.Len(t, entries, 1, "временные файлы не должны оставаться")
}
