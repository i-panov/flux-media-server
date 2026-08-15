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
type WatcherService struct {
	scanner     ScannerInterface
	watcher     *fsnotify.Watcher
	debounce    *time.Timer
	debounceDur time.Duration
	mu          sync.Mutex
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
			// Only care about file creation and writes.
			if event.Op&(fsnotify.Create|fsnotify.Write) == 0 {
				continue
			}

			w.scheduleScan(ctx)
		case err, ok := <-watcher.Errors:
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
func (w *WatcherService) scheduleScan(ctx context.Context) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if w.debounce != nil {
		w.debounce.Stop()
	}

	w.debounce = time.AfterFunc(w.debounceDur, func() {
		log.Printf("watcher: file changes settled, triggering scan")
		if err := w.scanner.ScanAll(ctx); err != nil {
			log.Printf("watcher: scan error: %v", err)
		}
	})
}
