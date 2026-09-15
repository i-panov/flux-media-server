package services_test

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"flux/internal/services"
)

// MockScanner is a mock for the ScannerInterface
type MockScanner struct {
	mock.Mock
	scanCalled chan []services.FSEvent
	mu         sync.Mutex
	lastCtx    context.Context
	lastEvents []services.FSEvent
}

func (m *MockScanner) ScanPath(ctx context.Context, path string) error {
	args := m.Called(ctx, path)
	return args.Error(0)
}

// LastCtx возвращает контекст последнего вызова HandleFSEvents.
func (m *MockScanner) LastCtx() context.Context {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.lastCtx
}

// LastEvents возвращает события последнего вызова HandleFSEvents.
func (m *MockScanner) LastEvents() []services.FSEvent {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.lastEvents
}

func (m *MockScanner) HandleFSEvents(ctx context.Context, events []services.FSEvent) {
	m.Called(ctx, events)

	m.mu.Lock()
	m.lastCtx = ctx
	m.lastEvents = events
	m.mu.Unlock()

	// Signal that HandleFSEvents was called
	if m.scanCalled != nil {
		select {
		case m.scanCalled <- events:
		default:
		}
	}
}

func (m *MockScanner) ScanAll(ctx context.Context) error {
	args := m.Called(ctx)

	m.mu.Lock()
	m.lastCtx = ctx
	m.mu.Unlock()

	return args.Error(0)
}

func (m *MockScanner) GetScanStatus(key string) *services.ScanStatus {
	args := m.Called(key)
	return args.Get(0).(*services.ScanStatus)
}

func TestWatcherDebounce(t *testing.T) {
	// Burst событий должен свернуться в ОДИН вызов HandleFSEvents,
	// содержащий все уникальные пути (а не по скану на каждое событие).

	mockScanner := &MockScanner{
		scanCalled: make(chan []services.FSEvent, 10), // Buffer to avoid blocking
	}
	mockScanner.On("HandleFSEvents", mock.Anything, mock.Anything).Return()

	watcher := services.NewWatcherService(mockScanner)

	tempDir := t.TempDir()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))

	// Trigger multiple events rapidly (burst)
	for i := 0; i < 5; i++ {
		testFile := filepath.Join(tempDir, "test"+string(rune('0'+i))+".txt")
		err := os.WriteFile(testFile, []byte("test content"), 0644)
		require.NoError(t, err)

		// Small delay between events (but still within debounce window)
		time.Sleep(10 * time.Millisecond)
	}

	// Wait for debounce to trigger (2 seconds + some margin)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var events []services.FSEvent
	select {
	case events = <-mockScanner.scanCalled:
	case <-ctx.Done():
		t.Fatal("HandleFSEvents was not called within expected time")
	}

	// Give some time to ensure no second call happens
	time.Sleep(100 * time.Millisecond)

	watcher.Stop()

	// All 5 unique paths must be in the single batch.
	require.Len(t, events, 5, "burst из 5 файлов должен уйти одной пачкой")
	for _, ev := range events {
		require.Equal(t, filepath.Dir(ev.Path), tempDir)
	}

	mockScanner.AssertNumberOfCalls(t, "HandleFSEvents", 1)
}

func TestWatcherDisabled(t *testing.T) {
	// This test verifies that changes are ignored if watcher is not started

	mockScanner := &MockScanner{}
	watcher := services.NewWatcherService(mockScanner)

	// Note: NOT starting the watcher with StartWithPaths

	tempDir := t.TempDir()

	testFile := filepath.Join(tempDir, "test.txt")
	err := os.WriteFile(testFile, []byte("test content"), 0644)
	require.NoError(t, err)

	// Wait a bit to ensure no scan happens
	time.Sleep(100 * time.Millisecond)

	watcher.Stop()

	// Assert that HandleFSEvents was never called
	mockScanner.AssertNotCalled(t, "HandleFSEvents", mock.Anything, mock.Anything)
}

// TestWatcherRestartRecreatesContext: повторный StartWithPaths после Stop
// обязан создать НОВЫЙ контекст — иначе loop мгновенно выходит и обработка
// событий мертва навсегда (регрессия: старый cancel без пересоздания ctx).
func TestWatcherRestartRecreatesContext(t *testing.T) {
	mockScanner := &MockScanner{
		scanCalled: make(chan []services.FSEvent, 10),
	}
	mockScanner.On("HandleFSEvents", mock.Anything, mock.Anything).Return()

	watcher := services.NewWatcherService(mockScanner)
	tempDir := t.TempDir()

	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))
	watcher.Stop()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))

	testFile := filepath.Join(tempDir, "restart.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte("x"), 0644))

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	select {
	case <-mockScanner.scanCalled:
	case <-ctx.Done():
		t.Fatal("HandleFSEvents was not called after restart: watcher is dead")
	}

	// Обработка обязана пройти с ЖИВЫМ контекстом нового запуска, а не со
	// старым отменённым.
	lastCtx := mockScanner.LastCtx()
	require.NotNil(t, lastCtx, "HandleFSEvents должен получить контекст")
	require.NoError(t, lastCtx.Err(), "HandleFSEvents получил отменённый контекст после рестарта")

	mockScanner.AssertNumberOfCalls(t, "HandleFSEvents", 1)
	watcher.Stop()
}

// TestWatcherRestartTwice: два рестарта подряд тоже не убивают watcher.
func TestWatcherRestartTwice(t *testing.T) {
	mockScanner := &MockScanner{
		scanCalled: make(chan []services.FSEvent, 10),
	}
	mockScanner.On("HandleFSEvents", mock.Anything, mock.Anything).Return()

	watcher := services.NewWatcherService(mockScanner)
	tempDir := t.TempDir()

	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))
	watcher.Stop()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))
	watcher.Stop()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))

	testFile := filepath.Join(tempDir, "restart2.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte("x"), 0644))

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	select {
	case <-mockScanner.scanCalled:
	case <-ctx.Done():
		t.Fatal("HandleFSEvents was not called after second restart")
	}

	lastCtx := mockScanner.LastCtx()
	require.NotNil(t, lastCtx)
	require.NoError(t, lastCtx.Err(), "HandleFSEvents получил отменённый контекст после второго рестарта")
}

// TestWatcherWatchesNewSubdirectory: директория, созданная ПОСЛЕ старта
// watcher'а, тоже отслеживается (fsnotify не делает этого сам).
// AddPath для новой директории асинхронен, поэтому создание файла
// повторяется с ретраями: событие может быть потеряно, если файл
// записан до применения watcher.Add.
func TestWatcherWatchesNewSubdirectory(t *testing.T) {
	mockScanner := &MockScanner{
		scanCalled: make(chan []services.FSEvent, 10),
	}
	mockScanner.On("HandleFSEvents", mock.Anything, mock.Anything).Return()

	watcher := services.NewWatcherService(mockScanner)
	tempDir := t.TempDir()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))
	defer watcher.Stop()

	subDir := filepath.Join(tempDir, "season1")
	require.NoError(t, os.Mkdir(subDir, 0755))

	testFile := filepath.Join(subDir, "episode.mp4")

	// Ретраи компенсируют асинхронность AddPath: событие на файл,
	// созданный до применения Add, теряется — пробуем снова. Ожидание
	// в попытке покрывает debounce-окно (2с) + запас.
	var got []services.FSEvent
	for attempt := 0; attempt < 5; attempt++ {
		require.NoError(t, os.WriteFile(testFile, []byte("x"), 0644))

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		select {
		case ev := <-mockScanner.scanCalled:
			got = ev
			cancel()
			require.NotEmpty(t, got)
			require.Equal(t, testFile, got[0].Path)
			return // успех: файл в новой подпапке отслежен
		case <-ctx.Done():
		}
		cancel()

		// Событие потеряно — удаляем файл и пробуем после паузы.
		_ = os.Remove(testFile)
		time.Sleep(300 * time.Millisecond)
	}
	t.Fatal("file in new subdirectory was not detected: fsnotify does not watch it")
}

// TestWatcherRemoveEvent: события Remove/Rename передаются сканеру как есть
// (он удаляет запись); операция в FSEvent обязана сохраниться.
func TestWatcherRemoveEvent(t *testing.T) {
	mockScanner := &MockScanner{
		scanCalled: make(chan []services.FSEvent, 10),
	}
	mockScanner.On("HandleFSEvents", mock.Anything, mock.Anything).Return()

	watcher := services.NewWatcherService(mockScanner)
	tempDir := t.TempDir()
	require.NoError(t, watcher.StartWithPaths([]string{tempDir}))
	defer watcher.Stop()

	testFile := filepath.Join(tempDir, "gone.mp4")
	require.NoError(t, os.WriteFile(testFile, []byte("x"), 0644))
	time.Sleep(100 * time.Millisecond)
	require.NoError(t, os.Remove(testFile))

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	select {
	case events := <-mockScanner.scanCalled:
		found := false
		for _, ev := range events {
			if ev.Path == testFile {
				found = true
				require.True(t, ev.Op&fsnotify.Remove != 0, "операция Remove должна сохраниться в FSEvent")
			}
		}
		require.True(t, found, "событие удаления должно попасть в пачку")
	case <-ctx.Done():
		t.Fatal("HandleFSEvents was not called after file removal")
	}
}
