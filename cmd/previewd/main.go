package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"github.com/Timo-In/code-preview.nvim/internal/snapshot"
	"github.com/Timo-In/code-preview.nvim/internal/transport"
	"github.com/Timo-In/code-preview.nvim/internal/watcher"
)

func main() {
	log.SetOutput(os.Stdout)
	socketPath := flag.String("socket", "", "Path to Neovim listen socket")
	worktreeRoot := flag.String("worktree", ".", "Root of git worktree")
	targetPath := flag.String("path", ".", "Target directory or file to watch")
	debounceMs := flag.Int("debounce", 80, "Debounce duration in milliseconds")
	flag.Parse()

	if *socketPath == "" {
		log.Fatal("Error: --socket is required")
	}

	absWorktree := canonicalPath(*worktreeRoot)
	absTarget := canonicalPath(*targetPath)
	if !pathWithin(absWorktree, absTarget) {
		log.Fatalf("[previewd] Target %s is outside worktree %s", absTarget, absWorktree)
	}

	log.Printf("[previewd] Starting Go Preview Daemon...")
	log.Printf("[previewd] Socket: %s", *socketPath)
	log.Printf("[previewd] Worktree: %s", absWorktree)
	log.Printf("[previewd] Target: %s", absTarget)

	// Connect to Neovim msgpack RPC
	client, err := transport.Connect(*socketPath)
	if err != nil {
		log.Fatalf("[previewd] Connection failed: %v", err)
	}
	defer client.Close()

	store := snapshot.NewStore()

	// Initialise watcher
	w, err := watcher.NewWatcher(*debounceMs, func(settledPath string) {
		settledPath = canonicalPath(settledPath)
		if !pathWithin(absWorktree, settledPath) {
			log.Printf("[previewd] Ignoring path outside worktree: %s", settledPath)
			return
		}
		key := snapshot.FileKey{
			WorktreeRoot: absWorktree,
			Path:         settledPath,
		}

		p, changes, targetLine, changed, err := store.UpdateFromFile(key)
		if err != nil {
			log.Printf("[previewd] Read error on %s: %v", settledPath, err)
			return
		}
		if !changed {
			return
		}

		payload := transport.UpdatePayload{
			WorktreeRoot: absWorktree,
			Path:         settledPath,
			Lines:        p.Current,
			Changes:      changes,
			TargetLine:   targetLine,
			Revision:     p.Revision,
		}

		if err := client.SendInPlaceUpdate(payload); err != nil {
			log.Printf("[previewd] Send update failed: %v", err)
		} else {
			log.Printf("[previewd] In-place update sent for %s (rev=%d, changes=%d)", settledPath, p.Revision, len(changes))
		}
	})
	if err != nil {
		log.Fatalf("[previewd] Failed to create watcher: %v", err)
	}
	defer w.Close()

	if err := w.AddPath(absTarget); err != nil {
		log.Fatalf("[previewd] Failed to add watch path %s: %v", absTarget, err)
	}

	log.Printf("[previewd] Watching %s with debounce %dms", absTarget, *debounceMs)

	// Stop when explicitly signalled or when the owning Neovim disconnects.
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sigChan)

	select {
	case <-sigChan:
		log.Printf("[previewd] Received termination signal.")
	case err := <-client.Disconnected():
		if err != nil {
			log.Printf("[previewd] Neovim RPC disconnected: %v", err)
		} else {
			log.Printf("[previewd] Neovim RPC disconnected.")
		}
	}

	log.Printf("[previewd] Shutting down daemon gracefully.")
}

func canonicalPath(p string) string {
	real, err := filepath.EvalSymlinks(p)
	if err == nil {
		return filepath.Clean(real)
	}
	abs, err := filepath.Abs(p)
	if err == nil {
		return filepath.Clean(abs)
	}
	return filepath.Clean(p)
}

func pathWithin(root, path string) bool {
	rel, err := filepath.Rel(root, path)
	if err != nil || filepath.IsAbs(rel) {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}
