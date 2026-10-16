package snapshot

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"sync"

	"github.com/Timo-In/code-preview.nvim/internal/diff"
)

// FileKey identifies a unique file in a worktree
type FileKey struct {
	WorktreeRoot string `json:"worktree_root"`
	Path         string `json:"path"` // Absolute normalized path
}

// FilePreview tracks dual-baselines and revision for a single file
type FilePreview struct {
	Key      FileKey
	Baseline []string
	Previous []string
	Current  []string
	Revision uint64
	Hash     string
}

// Store thread-safely manages previews for all observed files
type Store struct {
	mu       sync.RWMutex
	previews map[string]*FilePreview
}

func NewStore() *Store {
	return &Store{
		previews: make(map[string]*FilePreview),
	}
}

// UpdateFromFile reads file from disk, updates Previous and Current, and returns net changes
func (s *Store) UpdateFromFile(key FileKey) (*FilePreview, []diff.Change, int, bool, error) {
	data, err := os.ReadFile(key.Path)
	if err != nil {
		return nil, nil, 0, false, err
	}

	h := sha256.Sum256(data)
	hashStr := hex.EncodeToString(h[:])
	lines := diff.SplitLines(string(data))

	s.mu.Lock()
	defer s.mu.Unlock()

	p, exists := s.previews[key.Path]
	if !exists {
		// First observation: Baseline is the current disk state
		p = &FilePreview{
			Key:      key,
			Baseline: lines,
			Previous: lines,
			Current:  lines,
			Revision: 1,
			Hash:     hashStr,
		}
		s.previews[key.Path] = p
		// No changes relative to initial observation
		return p, []diff.Change{}, 1, true, nil
	}

	// If content hash hasn't changed, skip
	if p.Hash == hashStr {
		return p, nil, 0, false, nil
	}

	p.Revision++
	p.Previous = p.Current
	p.Current = lines
	p.Hash = hashStr

	// Calculate net changes relative to round baseline
	netChanges := diff.ComputeNetChanges(p.Baseline, p.Current)
	targetLine := diff.FindFirstEditLine(p.Previous, p.Current)

	return p, netChanges, targetLine, true, nil
}

// FreezeBaseline freezes current state as the new baseline (e.g. on agent turn complete)
func (s *Store) FreezeBaseline(path string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if p, ok := s.previews[path]; ok {
		p.Baseline = p.Current
		p.Previous = p.Current
	}
}

// Clear removes a file from preview store
func (s *Store) Clear(path string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.previews, path)
}
