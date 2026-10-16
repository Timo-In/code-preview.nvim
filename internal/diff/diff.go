package diff

import (
	"strings"
)

// Change represents a net change hunk to be rendered by Neovim
type Change struct {
	Type         string   `json:"type"`          // "add", "change", "delete"
	StartLine    int      `json:"start_line"`    // 1-indexed, inclusive
	EndLine      int      `json:"end_line"`      // 1-indexed, inclusive
	AtLine       int      `json:"at_line"`       // 1-indexed line where virtual deletion is attached
	DeletedLines []string `json:"deleted_lines"` // Text of deleted lines
}

// ComputeNetChanges computes diff between baseline and current lines
func ComputeNetChanges(baseline, current []string) []Change {
	// Standard Longest Common Subsequence (LCS) based diff
	n := len(baseline)
	m := len(current)

	dp := make([][]int, n+1)
	for i := range dp {
		dp[i] = make([]int, m+1)
	}

	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			if baseline[i-1] == current[j-1] {
				dp[i][j] = dp[i-1][j-1] + 1
			} else {
				if dp[i-1][j] >= dp[i][j-1] {
					dp[i][j] = dp[i-1][j]
				} else {
					dp[i][j] = dp[i][j-1]
				}
			}
		}
	}

	// Backtrack to find diff operations
	type op struct {
		kind string // "equal", "delete", "insert"
		line string
		idxB int // 1-indexed in baseline
		idxC int // 1-indexed in current
	}
	var ops []op

	i, j := n, m
	for i > 0 || j > 0 {
		if i > 0 && j > 0 && baseline[i-1] == current[j-1] {
			ops = append(ops, op{kind: "equal", line: baseline[i-1], idxB: i, idxC: j})
			i--
			j--
		} else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
			ops = append(ops, op{kind: "insert", line: current[j-1], idxC: j})
			j--
		} else if i > 0 && (j == 0 || dp[i][j-1] < dp[i-1][j]) {
			ops = append(ops, op{kind: "delete", line: baseline[i-1], idxB: i})
			i--
		}
	}

	// Reverse ops to chronological order
	for k := 0; k < len(ops)/2; k++ {
		ops[k], ops[len(ops)-1-k] = ops[len(ops)-1-k], ops[k]
	}

	var changes []Change
	k := 0
	for k < len(ops) {
		if ops[k].kind == "equal" {
			k++
			continue
		}

		var delLines []string
		insertStart := 0
		insertEnd := 0

		// Group contiguous insert / delete operations into a hunk
		for k < len(ops) && ops[k].kind != "equal" {
			if ops[k].kind == "delete" {
				delLines = append(delLines, ops[k].line)
			} else if ops[k].kind == "insert" {
				if insertStart == 0 {
					insertStart = ops[k].idxC
				}
				insertEnd = ops[k].idxC
			}
			k++
		}

		if len(delLines) > 0 && insertStart > 0 {
			// Combination of delete and insert => Change
			changes = append(changes, Change{
				Type:         "change",
				StartLine:    insertStart,
				EndLine:      insertEnd,
				AtLine:       insertStart,
				DeletedLines: delLines,
			})
		} else if insertStart > 0 {
			// Only insertions => Add
			changes = append(changes, Change{
				Type:      "add",
				StartLine: insertStart,
				EndLine:   insertEnd,
			})
		} else if len(delLines) > 0 {
			// Only deletions => Delete
			atLine := 1
			if k < len(ops) && ops[k].idxC > 0 {
				atLine = ops[k].idxC
			} else if k-len(delLines)-1 >= 0 && ops[k-len(delLines)-1].idxC > 0 {
				atLine = ops[k-len(delLines)-1].idxC
			}
			changes = append(changes, Change{
				Type:         "delete",
				AtLine:       atLine,
				DeletedLines: delLines,
			})
		}
	}

	return changes
}

// FindFirstEditLine compares previous and current to locate the newest modified line
func FindFirstEditLine(previous, current []string) int {
	minLen := len(previous)
	if len(current) < minLen {
		minLen = len(current)
	}

	for idx := 0; idx < minLen; idx++ {
		if previous[idx] != current[idx] {
			return idx + 1
		}
	}

	if len(current) > len(previous) {
		return minLen + 1
	}
	return 1
}

// SplitLines splits file content into line array preserving empty lines without CR
func SplitLines(content string) []string {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	content = strings.ReplaceAll(content, "\r", "\n")
	if len(content) == 0 {
		return []string{}
	}
	lines := strings.Split(content, "\n")
	// If trailing newline exists, remove the trailing empty string to match editor line count
	if len(lines) > 0 && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines
}
