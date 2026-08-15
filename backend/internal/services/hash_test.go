package services

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestQuickHashDetectsTailChangeInMediumFile: файл ~1.5 МБ, байт меняется в
// хвосте [1МБ; конец) при том же размере. Хеш обязан измениться — иначе
// изменение файла останется незамеченным при повторном сканировании.
func TestQuickHashDetectsTailChangeInMediumFile(t *testing.T) {
	dir := t.TempDir()
	size := 1500 * 1024 // ~1.5 МБ
	fileA := filepath.Join(dir, "a.bin")
	fileB := filepath.Join(dir, "b.bin")

	base := bytes.Repeat([]byte{0xAB}, size)
	require.NoError(t, os.WriteFile(fileA, base, 0644))

	mod := make([]byte, size)
	copy(mod, base)
	mod[1200*1024] = 0xCD // изменение в зоне [1МБ; конец)
	require.NoError(t, os.WriteFile(fileB, mod, 0644))

	hashA, err := quickHashFile(context.Background(), fileA)
	require.NoError(t, err)
	hashB, err := quickHashFile(context.Background(), fileB)
	require.NoError(t, err)
	assert.NotEqual(t, hashA, hashB, "изменение хвоста файла 1.5 МБ должно менять quick hash")
}

// TestQuickHashSameForUnchangedFile: одинаковые файлы дают одинаковые хеши.
func TestQuickHashSameForUnchangedFile(t *testing.T) {
	dir := t.TempDir()
	fileA := filepath.Join(dir, "a.bin")
	fileB := filepath.Join(dir, "b.bin")

	content := bytes.Repeat([]byte{0xAB}, 1500*1024)
	require.NoError(t, os.WriteFile(fileA, content, 0644))
	require.NoError(t, os.WriteFile(fileB, content, 0644))

	hashA, err := quickHashFile(context.Background(), fileA)
	require.NoError(t, err)
	hashB, err := quickHashFile(context.Background(), fileB)
	require.NoError(t, err)
	assert.Equal(t, hashA, hashB)
}

// TestHashCancelledContext: отмена контекста прерывает хеширование.
func TestHashCancelledContext(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "a.bin")
	require.NoError(t, os.WriteFile(file, bytes.Repeat([]byte{0x01}, 4096), 0644))

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := quickHashFile(ctx, file)
	assert.ErrorIs(t, err, context.Canceled)

	_, err = HashFileContext(ctx, file)
	assert.ErrorIs(t, err, context.Canceled)
}

// TestQuickHashBeforeOpen: отменённый контекст прерывает ещё до открытия файла.
func TestQuickHashBeforeOpen(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	_, err := quickHashFile(ctx, filepath.Join(t.TempDir(), "nonexistent.bin"))
	assert.ErrorIs(t, err, context.Canceled)
}
