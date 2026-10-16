package main

import (
	"path/filepath"
	"testing"
)

func TestPathWithin(t *testing.T) {
	root := filepath.Join(string(filepath.Separator), "work", "project")
	tests := []struct {
		name string
		path string
		want bool
	}{
		{name: "root", path: root, want: true},
		{name: "child", path: filepath.Join(root, "src", "main.go"), want: true},
		{name: "sibling prefix", path: root + "-other", want: false},
		{name: "parent", path: filepath.Dir(root), want: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := pathWithin(root, tt.path); got != tt.want {
				t.Fatalf("pathWithin(%q, %q) = %v, want %v", root, tt.path, got, tt.want)
			}
		})
	}
}
