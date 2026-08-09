package services

import (
	"context"
	"log"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// WatcherService monitors library directories for new files using fsnotify.
type WatcherService struct {
	scanner     ScannerInterface
	watcher     *fsnotify.Watcher
	debounce    *time.Timer
	debounceDur time.Duration
	mu          sync.Mutex
	ctx         context.Context
	cancel      context.CancelFunc
}

// NewWatcherService creates a new WatcherService.
func NewWatcherService(scanner ScannerInterface) *WatcherService {
	ctx, cancel := context.WithCancel(context.Background())
	return &WatcherService{
		scanner:     scanner,
		debounceDur: 2 * time.Second,
		ctx:         ctx,
		cancel:      cancel,
	}
}

// StartWithPaths begins watching the given directory paths.
func (w *WatcherService) StartWithPaths(paths []string) error {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}

	w.mu.Lock()
	w.watcher = watcher
	w.mu.Unlock()

	go w.loop()

	for _, p := range paths {
		w.AddPath(p)
	}

	log.Printf("watcher: started, watching %d paths", len(paths))
	return nil
}

// AddPath adds a directory to watch.
func (w *WatcherService) AddPath(path string) {
	w.mu.Lock()
	watcher := w.watcher
	w.mu.Unlock()
	if watcher != nil {
		if err := watcher.Add(path); err != nil {
			log.Printf("watcher: add path %s: %v", path, err)
		} else {
			log.Printf("watcher: watching %s", path)
		}
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
	w.cancel()
	w.mu.Lock()
	watcher := w.watcher
	w.mu.Unlock()
	if watcher != nil {
		watcher.Close()
	}
	log.Println("watcher: stopped")
}

func (w *WatcherService) loop() {
	for {
		select {
		case <-w.ctx.Done():
			return
		case event, ok := <-w.watcher.Events:
			if !ok {
				return
			}
			// Only care about file creation and writes.
			if event.Op&(fsnotify.Create|fsnotify.Write) == 0 {
				continue
			}

			w.scheduleScan()
		case err, ok := <-w.watcher.Errors:
			if !ok {
				return
			}
			log.Printf("watcher: error: %v", err)
		}
	}
}

// scheduleScan resets a single global debounce timer: any burst of fs events
// results in exactly one ScanAll after the burst settles (instead of one full
// scan per event, which is O(events × library size)).
func (w *WatcherService) scheduleScan() {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.debounce != nil {
		w.debounce.Stop()
	}

	w.debounce = time.AfterFunc(w.debounceDur, func() {
		log.Printf("watcher: file changes settled, triggering scan")
		if err := w.scanner.ScanAll(w.ctx); err != nil {
			log.Printf("watcher: scan error: %v", err)
		}
	})
}
