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
	debounce    map[string]*time.Timer
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
		debounce:    make(map[string]*time.Timer),
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
	w.watcher = watcher

	go w.loop()

	for _, p := range paths {
		w.addPath(p)
	}

	log.Printf("watcher: started, watching %d paths", len(paths))
	return nil
}

// AddPath adds a directory to watch.
func (w *WatcherService) AddPath(path string) {
	w.addPath(path)
}

// RemovePath removes a directory from watch.
func (w *WatcherService) RemovePath(path string) {
	if w.watcher != nil {
		w.watcher.Remove(path)
	}
	log.Printf("watcher: stopped watching %s", path)
}

// Stop stops the watcher.
func (w *WatcherService) Stop() {
	w.cancel()
	if w.watcher != nil {
		w.watcher.Close()
	}
	// Cancel all pending debounce timers.
	w.mu.Lock()
	for path, timer := range w.debounce {
		timer.Stop()
		delete(w.debounce, path)
	}
	w.mu.Unlock()
	log.Println("watcher: stopped")
}

func (w *WatcherService) addPath(path string) {
	if w.watcher != nil {
		if err := w.watcher.Add(path); err != nil {
			log.Printf("watcher: add path %s: %v", path, err)
		} else {
			log.Printf("watcher: watching %s", path)
		}
	}
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
			// Skip directories.
			if event.Has(fsnotify.Create) {
				// We can't easily check if it's a dir from the event,
				// but the scanner handles directories gracefully.
			}

			w.debouncePath(event.Name)
		case err, ok := <-w.watcher.Errors:
			if !ok {
				return
			}
			log.Printf("watcher: error: %v", err)
		}
	}
}

func (w *WatcherService) debouncePath(path string) {
	w.mu.Lock()
	defer w.mu.Unlock()

	if timer, exists := w.debounce[path]; exists {
		timer.Stop()
	}

	w.debounce[path] = time.AfterFunc(w.debounceDur, func() {
		w.mu.Lock()
		delete(w.debounce, path)
		w.mu.Unlock()

		log.Printf("watcher: triggering scan for %s", path)
		// Scan all libraries — the scanner will pick up the new file.
		go func() {
			if err := w.scanner.ScanAll(w.ctx); err != nil {
				log.Printf("watcher: scan error: %v", err)
			}
		}()
	})
}
