package services

import (
	"errors"
	"fmt"
	"path/filepath"
	"sort"
	"strings"
	"unicode"
	"unicode/utf8"
)

// ErrInvalidFilename is returned when a filename contains path separators,
// traversal sequences or control characters.
var ErrInvalidFilename = errors.New("invalid filename")

// ErrInvalidDirname is returned for empty content directory paths.
var ErrInvalidDirname = errors.New("content directory path is empty")

// SanitizeFilename validates a user-supplied filename and returns its base
// name. It rejects names containing path separators, traversal sequences
// and control characters (включая \n\r\t: на диске они легальны, но
// ломают логи/отображение и расползаются по shell-инвокациям).
func SanitizeFilename(name string) (string, error) {
	if name == "" {
		return "", ErrInvalidFilename
	}
	if !utf8.ValidString(name) {
		return "", ErrInvalidFilename
	}
	if strings.IndexFunc(name, unicode.IsControl) >= 0 {
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

// ValidateContentDirs проверяет каталоги контента: пустых быть не
// должно, пересекаться и вкладываться друг в друга — тоже (иначе сканер
// проиндексирует карантин как библиотеку, а чистка удалит не то).
// Возвращает первую найденную проблему.
func ValidateContentDirs(named map[string]string) error {
	clean := make(map[string]string, len(named))
	for name, dir := range named {
		if dir == "" {
			return ErrInvalidDirname
		}
		clean[name] = filepath.Clean(dir)
	}
	names := make([]string, 0, len(clean))
	for name := range clean {
		names = append(names, name)
	}
	sort.Strings(names)
	for i := 0; i < len(names); i++ {
		for j := i + 1; j < len(names); j++ {
			a, b := clean[names[i]], clean[names[j]]
			if a == b || IsSubPath(a, b) || IsSubPath(b, a) {
				return fmt.Errorf("content dirs overlap: %s (%s) and %s (%s)", names[i], a, names[j], b)
			}
		}
	}
	return nil
}

// LibraryPathFromName builds a library directory path from a user-supplied
// name, ensuring the result stays inside baseDir.
func LibraryPathFromName(baseDir, name string) (string, error) {
	if name == "" || name == "." || name == ".." {
		return "", ErrInvalidFilename
	}
	if !utf8.ValidString(name) {
		return "", ErrInvalidFilename
	}
	if strings.IndexFunc(name, unicode.IsControl) >= 0 {
		return "", ErrInvalidFilename
	}
	if strings.ContainsAny(name, "/\\") {
		return "", ErrInvalidFilename
	}
	dirName := strings.ReplaceAll(name, " ", "_")
	p := filepath.Join(baseDir, dirName)
	if !IsSubPath(baseDir, p) {
		return "", ErrInvalidFilename
	}
	return p, nil
}
