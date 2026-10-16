package diff

import (
	"testing"
)

func TestComputeNetChanges(t *testing.T) {
	baseline := []string{
		"func add(a, b int) int {",
		"    legacy := 10",
		"    return a + b",
		"}",
	}

	current := []string{
		"func add(a, b int) int {",
		"    return a + b",
		"}",
		"// new line",
	}

	changes := ComputeNetChanges(baseline, current)
	if len(changes) == 0 {
		t.Fatalf("expected changes, got none")
	}

	hasDelete := false
	hasAdd := false
	for _, c := range changes {
		if c.Type == "delete" {
			hasDelete = true
			if len(c.DeletedLines) != 1 || c.DeletedLines[0] != "    legacy := 10" {
				t.Errorf("unexpected deleted lines: %v", c.DeletedLines)
			}
		}
		if c.Type == "add" {
			hasAdd = true
			if c.StartLine != 4 {
				t.Errorf("expected added line at 4, got %d", c.StartLine)
			}
		}
	}

	if !hasDelete {
		t.Errorf("expected delete change hunk")
	}
	if !hasAdd {
		t.Errorf("expected add change hunk")
	}
}

func TestFindFirstEditLine(t *testing.T) {
	prev := []string{"line1", "line2", "line3"}
	curr := []string{"line1", "line2_mod", "line3"}

	line := FindFirstEditLine(prev, curr)
	if line != 2 {
		t.Fatalf("expected line 2, got %d", line)
	}
}
