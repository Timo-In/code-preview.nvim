package snapshot

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSnapshotStore_UpdateFromFile(t *testing.T) {
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "test.txt")

	// 1. Initial write (Baseline V0)
	if err := os.WriteFile(filePath, []byte("line 1\nline 2\n"), 0644); err != nil {
		t.Fatal(err)
	}

	store := NewStore()
	key := FileKey{WorktreeRoot: tmpDir, Path: filePath}

	p, changes, _, changed, err := store.UpdateFromFile(key)
	if err != nil || !changed {
		t.Fatalf("first observation failed: %v", err)
	}
	if len(changes) != 0 {
		t.Fatalf("expected 0 net changes on first observation, got %d", len(changes))
	}

	// 2. Modify file (V1)
	if err := os.WriteFile(filePath, []byte("line 1\nline 2 modified\nline 3\n"), 0644); err != nil {
		t.Fatal(err)
	}

	p, changes, target, changed, err := store.UpdateFromFile(key)
	if err != nil || !changed {
		t.Fatalf("second observation failed: %v", err)
	}
	if p.Revision != 2 {
		t.Errorf("expected revision 2, got %d", p.Revision)
	}
	if len(changes) == 0 {
		t.Fatalf("expected changes, got 0")
	}
	if target != 2 {
		t.Errorf("expected target line 2, got %d", target)
	}
}
