package watcher

import (
	"log"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

// Watcher debounces filesystem notifications for active files
type Watcher struct {
	fsWatcher *fsnotify.Watcher
	debounce  time.Duration
	onSettled func(path string)
	mu        sync.Mutex
	timers    map[string]*time.Timer
	stopChan  chan struct{}
}

func NewWatcher(debounceMs int, onSettled func(path string)) (*Watcher, error) {
	fw, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, err
	}

	w := &Watcher{
		fsWatcher: fw,
		debounce:  time.Duration(debounceMs) * time.Millisecond,
		onSettled: onSettled,
		timers:    make(map[string]*time.Timer),
		stopChan:  make(chan struct{}),
	}

	go w.eventLoop()
	return w, nil
}

func (w *Watcher) AddPath(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	return w.fsWatcher.Add(abs)
}

func (w *Watcher) RemovePath(path string) error {
	abs, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	return w.fsWatcher.Remove(abs)
}

func (w *Watcher) Close() error {
	close(w.stopChan)
	return w.fsWatcher.Close()
}

func (w *Watcher) eventLoop() {
	for {
		select {
		case <-w.stopChan:
			return
		case event, ok := <-w.fsWatcher.Events:
			if !ok {
				return
			}
			// Only debounce Write, Create, or Rename (atomic replace) events
			if event.Has(fsnotify.Write) || event.Has(fsnotify.Create) || event.Has(fsnotify.Rename) {
				w.triggerDebounce(event.Name)
			}
		case err, ok := <-w.fsWatcher.Errors:
			if !ok {
				return
			}
			log.Printf("[watcher] error: %v", err)
		}
	}
}

func (w *Watcher) triggerDebounce(path string) {
	abs, err := filepath.Abs(path)
	if err != nil {
		abs = path
	}

	w.mu.Lock()
	defer w.mu.Unlock()

	if t, exists := w.timers[abs]; exists {
		t.Stop()
	}

	w.timers[abs] = time.AfterFunc(w.debounce, func() {
		w.mu.Lock()
		delete(w.timers, abs)
		w.mu.Unlock()

		if w.onSettled != nil {
			w.onSettled(abs)
		}
	})
}
