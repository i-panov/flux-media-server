package services

import (
	"errors"
	"path/filepath"
	"strings"
)

// ErrInvalidFilename is returned when a filename contains path separators,
// traversal sequences or control characters.
var ErrInvalidFilename = errors.New("invalid filename")

// SanitizeFilename validates a user-supplied filename and returns its base
// name. It rejects names containing path separators, traversal sequences,
// NUL bytes and control characters.
func SanitizeFilename(name string) (string, error) {
	if name == "" {
		return "", ErrInvalidFilename
	}
	if strings.ContainsRune(name, 0) {
		return "", ErrInvalidFilename
	}
	if strings.ContainsAny(name, "/\\") {
		return "", ErrInvalidFilename
	}
	base := filepath.Base(name)
	if base == "." || base == ".." || base != name {
		return "", ErrInvalidFilename
	}
	return base, nil
}

// IsSubPath reports whether path is inside baseDir after cleaning.
// Both paths should already be absolute for a reliable result.
func IsSubPath(baseDir, path string) bool {
	cleanBase := filepath.Clean(baseDir)
	cleanPath := filepath.Clean(path)
	return cleanPath == cleanBase ||
		strings.HasPrefix(cleanPath, cleanBase+string(filepath.Separator))
}

// LibraryPathFromName builds a library directory path from a user-supplied
// name, ensuring the result stays inside baseDir.
func LibraryPathFromName(baseDir, name string) (string, error) {
	if strings.ContainsRune(name, 0) || strings.ContainsAny(name, "/\\") {
		return "", ErrInvalidFilename
	}
	if name == "" || name == "." || name == ".." {
		return "", ErrInvalidFilename
	}
	dirName := strings.ReplaceAll(name, " ", "_")
	p := filepath.Join(baseDir, dirName)
	if !IsSubPath(baseDir, p) {
		return "", ErrInvalidFilename
	}
	return p, nil
}
