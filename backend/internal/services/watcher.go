package services

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// WatcherService monitors library directories for new files using fsnotify.
//
// События обрабатываются инкрементально: watcher накапливает события за
// debounce-окно в map (путь → последняя операция) и по истечении окна
// передаёт пачку сканеру через HandleFSEvents. Полный ScanAll вызывается
// только вручную (первичный скан при старте, консольный режим).
type WatcherService struct {
	scanner     ScannerInterface
	watcher     *fsnotify.Watcher
	debounce    *time.Timer
	debounceDur time.Duration
	mu          sync.Mutex
	pending     map[string]fsnotify.Op
	ctx         context.Context
	cancel      context.CancelFunc
	isRunning   bool
}

// NewWatcherService creates a new WatcherService.
func NewWatcherService(scanner ScannerInterface) *WatcherService {
	ctx, cancel := context.WithCancel(context.Background())
	return &WatcherService{
		scanner:     scanner,
		debounceDur: 2 * time.Second,
		pending:     make(map[string]fsnotify.Op),
		ctx:         ctx,
		cancel:      cancel,
	}
}

// StartWithPaths begins watching the given directory paths.
// It is idempotent: if already running, it stops the old watcher and starts
// fresh. Each start creates a NEW context/cancel — the previous ctx (possibly
// cancelled by a prior Stop/restart) must never leak into the new loop.
func (w *WatcherService) StartWithPaths(paths []string) error {
	w.mu.Lock()
	if w.isRunning {
		w.cancel()
		if w.watcher != nil {
			w.watcher.Close()
		}
		w.watcher = nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		cancel()
		w.mu.Unlock()
		return err
	}

	w.ctx = ctx
	w.cancel = cancel
	w.watcher = watcher
	w.pending = make(map[string]fsnotify.Op)
	w.isRunning = true
	w.mu.Unlock()

	go w.loop(ctx, watcher)

	for _, p := range paths {
		w.AddPath(p)
	}

	log.Printf("watcher: started, watching %d paths", len(paths))
	return nil
}

// AddPath adds a directory to watch, including all subdirectories recursively.
func (w *WatcherService) AddPath(root string) {
	w.mu.Lock()
	watcher := w.watcher
	w.mu.Unlock()
	if watcher == nil {
		return
	}

	// Walk the directory tree and add each directory to fsnotify.
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			_ = watcher.Add(path) // ignore errors for already-watched dirs
			log.Printf("watcher: watching %s", path)
		}
		return nil
	})
	if err != nil {
		log.Printf("watcher: walk path %s: %v", root, err)
	}
}

// RemovePath removes a directory from watch.
func (w *WatcherService) RemovePath(path string) {
	w.mu.Lock()
	watcher := w.watcher
	w.mu.Unlock()
	if watcher != nil {
		watcher.Remove(path)
	}
	log.Printf("watcher: stopped watching %s", path)
}

// Stop stops the watcher and releases resources.
func (w *WatcherService) Stop() {
	w.mu.Lock()
	if !w.isRunning {
		w.mu.Unlock()
		return
	}
	w.isRunning = false
	w.cancel()
	if w.debounce != nil {
		w.debounce.Stop()
		w.debounce = nil
	}
	watcher := w.watcher
	w.mu.Unlock()
	if watcher != nil {
		watcher.Close()
	}
	log.Println("watcher: stopped")
}

// loop reads events from the given watcher. ctx and watcher are captured at
// start time (under w.mu in StartWithPaths) and passed as arguments: reading
// w.watcher/w.ctx here without the lock would race with Start/Stop writes.
func (w *WatcherService) loop(ctx context.Context, watcher *fsnotify.Watcher) {
	for {
		select {
		case <-ctx.Done():
			return
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			w.handleEvent(ctx, watcher, event)
		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			log.Printf("watcher: error: %v", err)
		}
	}
}

// handleEvent обрабатывает одно событие fsnotify: новые директории
// добавляются в watch, файловые события накапливаются в pending до
// истечения debounce-окна.
func (w *WatcherService) handleEvent(ctx context.Context, watcher *fsnotify.Watcher, event fsnotify.Event) {
	info, err := os.Stat(event.Name)
	if err == nil && info.IsDir() {
		// fsnotify не следит за новыми поддиректориями сам: Create
		// директории требует явного AddPath (рекурсивно, на случай
		// вложенных папок).
		if event.Op&fsnotify.Create != 0 {
			go w.AddPath(event.Name)
		}
		// Директории не участвуют в обработке медиа-записей.
		return
	}

	w.mu.Lock()
	w.pending[event.Name] = event.Op
	w.mu.Unlock()

	w.scheduleFlush(ctx)
}

// scheduleFlush сбрасывает debounce-таймер: пачка событий уходит сканеру
// через debounceDur после ПОСЛЕДНЕГО события (burst копирования файла
// шлёт десятки Write — все сворачиваются в одну обработку).
func (w *WatcherService) scheduleFlush(ctx context.Context) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.debounce != nil {
		w.debounce.Stop()
	}

	w.debounce = time.AfterFunc(w.debounceDur, func() {
		events := w.takePending()
		if len(events) == 0 {
			return
		}
		w.scanner.HandleFSEvents(ctx, events)
	})
}

// takePending снимает снапшот накопленных событий и очищивает буфер.
func (w *WatcherService) takePending() []FSEvent {
	w.mu.Lock()
	defer w.mu.Unlock()

	events := make([]FSEvent, 0, len(w.pending))
	for path, op := range w.pending {
		events = append(events, FSEvent{Path: path, Op: op})
	}
	w.pending = make(map[string]fsnotify.Op)
	return events
}
