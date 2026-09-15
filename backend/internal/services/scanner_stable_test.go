package services

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Тесты waitUntilFileStable — детерминированные: малые интервалы
// (миллисекунды) вместо продакшен-констант (300 мс), поэтому писатель
// гарантированно укладывается между замерами.

// TestWaitUntilFileStableStableFile: файл, который никто не пишет,
// признаётся стабильным со второй попытки (первая — базовый замер).
func TestWaitUntilFileStableStableFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stable.mp4")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))

	start := time.Now()
	ok := waitUntilFileStable(context.Background(), path, 3, 5*time.Millisecond)
	assert.True(t, ok)
	// Стабильный файл: два замера подряд совпали — вторая попытка сразу.
	assert.Less(t, time.Since(start), 15*time.Millisecond, "стабильный файл не должен ждать все попытки")
}

// TestWaitUntilFileStableGrowingFile: файл, дописываемый чаще интервала
// выборки, не признаётся стабильным — ни размер, ни mtime не совпадут.
func TestWaitUntilFileStableGrowingFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "growing.mp4")
	require.NoError(t, os.WriteFile(path, []byte("x"), 0644))

	stop := make(chan struct{})
	go func() {
		defer close(stop)
		for i := 0; i < 200; i++ {
			f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0644)
			if err != nil {
				return
			}
			_, _ = f.WriteString("0123456789")
			_ = f.Close()
			time.Sleep(2 * time.Millisecond)
		}
	}()
	defer func() { <-stop }()

	ok := waitUntilFileStable(context.Background(), path, 3, 10*time.Millisecond)
	assert.False(t, ok, "растущий файл не должен признаваться стабильным")
}

// TestWaitUntilFileStableMissingFile: отсутствующий файл — false, не ошибка.
func TestWaitUntilFileStableMissingFile(t *testing.T) {
	ok := waitUntilFileStable(context.Background(), filepath.Join(t.TempDir(), "nope.mp4"), 3, 5*time.Millisecond)
	assert.False(t, ok)
}

// TestWaitUntilFileStableCancelledContext: отменённый контекст — false
// без ожидания.
func TestWaitUntilFileStableCancelledContext(t *testing.T) {
	path := filepath.Join(t.TempDir(), "stable.mp4")
	require.NoError(t, os.WriteFile(path, []byte("content"), 0644))

	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	start := time.Now()
	ok := waitUntilFileStable(ctx, path, 3, 5*time.Millisecond)
	assert.False(t, ok)
	assert.Less(t, time.Since(start), 5*time.Millisecond, "отменённый контекст не должен ждать")
}
