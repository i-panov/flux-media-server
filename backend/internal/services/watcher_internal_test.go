package services

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// stubWatcherScanner — минимальный ScannerInterface для внутренних тестов
// watcher'а (нужен доступ к приватным полям: debounce, debounceDur).
type stubWatcherScanner struct {
	mu     sync.Mutex
	calls  int
	lastCT context.Context
	got    chan []FSEvent
}

func (s *stubWatcherScanner) ScanPath(context.Context, string) error { return nil }
func (s *stubWatcherScanner) ScanAll(context.Context) error          { return nil }
func (s *stubWatcherScanner) GetScanStatus(string) *ScanStatus       { return nil }

func (s *stubWatcherScanner) HandleFSEvents(ctx context.Context, events []FSEvent) {
	s.mu.Lock()
	s.calls++
	s.lastCT = ctx
	s.mu.Unlock()
	if s.got != nil {
		select {
		case s.got <- events:
		default:
		}
	}
}

func (s *stubWatcherScanner) numCalls() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.calls
}

// TestWatcherRestartStopsOldDebounceTimer: рестарт через StartWithPaths
// без Stop обязан остановить старый debounce-таймер (зеркало Stop):
// иначе он срабатывает с отменённым ctx и забирает takePending из
// пересозданной карты.
func TestWatcherRestartStopsOldDebounceTimer(t *testing.T) {
	sc := &stubWatcherScanner{}
	w := NewWatcherService(sc)
	dir := t.TempDir()

	require.NoError(t, w.StartWithPaths([]string{dir}))
	defer w.Stop()

	w.mu.Lock()
	w.debounce = time.AfterFunc(time.Hour, func() {})
	old := w.debounce
	w.mu.Unlock()
	require.NotNil(t, old)

	require.NoError(t, w.StartWithPaths([]string{dir}))

	assert.False(t, old.Stop(), "старый debounce-таймер обязан быть остановлен рестартом")

	w.mu.Lock()
	assert.Nil(t, w.debounce, "после рестарта без событий таймера быть не должно")
	w.mu.Unlock()
}

// TestWatcherRestartWhileRunningDeliversWithLiveCtx: рестарт на ходу
// (два StartWithPaths подряд) не теряет новые события и не зовёт сканер
// с отменённым контекстом старого запуска.
func TestWatcherRestartWhileRunningDeliversWithLiveCtx(t *testing.T) {
	sc := &stubWatcherScanner{got: make(chan []FSEvent, 10)}
	w := NewWatcherService(sc)
	w.debounceDur = 50 * time.Millisecond
	dir := t.TempDir()

	require.NoError(t, w.StartWithPaths([]string{dir}))
	defer w.Stop()

	// Событие до рестарта взводит старый таймер — рестарт идёт СРАЗУ,
	// до его срабатывания: без фикса он выстрелил бы позже с отменённым
	// ctx, забрав takePending из пересозданной карты.
	require.NoError(t, os.WriteFile(filepath.Join(dir, "before.mp4"), []byte("x"), 0644))

	// ...рестарт на ходу, затем новое событие уже в новом запуске.
	require.NoError(t, w.StartWithPaths([]string{dir}))
	afterPath := filepath.Join(dir, "after.mp4")
	require.NoError(t, os.WriteFile(afterPath, []byte("y"), 0644))

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var got []FSEvent
	select {
	case got = <-sc.got:
	case <-ctx.Done():
		t.Fatal("HandleFSEvents не вызван после рестарта на ходу")
	}
	found := false
	for _, ev := range got {
		if ev.Path == afterPath {
			found = true
		}
	}
	assert.True(t, found, "пачка после рестарта обязана содержать новое событие")

	// Старый таймер не должен довызвать сканер с отменённым ctx:
	// ждём дольше старого debounce-окна и проверяем единственный вызов.
	time.Sleep(200 * time.Millisecond)
	assert.Equal(t, 1, sc.numCalls(), "старый таймер не должен дублировать вызов после рестарта")

	sc.mu.Lock()
	lastCT := sc.lastCT
	sc.mu.Unlock()
	require.NotNil(t, lastCT)
	require.NoError(t, lastCT.Err(), "HandleFSEvents вызван с отменённым контекстом старого запуска")
}
