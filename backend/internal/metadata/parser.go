package metadata

import (
	"regexp"
	"strconv"
	"strings"
)

var (
	dotPattern     = regexp.MustCompile(`(?i)^(.+)\.(\d{4})\.[^.]+$`)
	parenPattern   = regexp.MustCompile(`(?i)^(.+?)\s*\((\d{4})\)\.[^.]+$`)
	episodePattern = regexp.MustCompile(`(?i)^(.+)\.S(\d{2})E(\d{2})\..+$`)
)

// ParseFilenameUpload parses a filename (without directory path) to extract title and year.
func ParseFilenameUpload(filename string) (string, int) {
	return ParseFilename(filename)
}

func ParseFilename(filename string) (string, int) {
	// Episode pattern must come before paren/dot patterns:
	// "Show Name (2020) S01E01.mkv" should be parsed as TV show,
	// not as a movie with year 2020.
	if matches := episodePattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		return strings.TrimSpace(title), 0
	}

	// Parenthesized year: "Movie Name (2020).mkv" → title "Movie Name", year 2020
	// Must come before dotPattern which would match "Movie Name (2020)" + year.
	if matches := parenPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.TrimSpace(matches[1])
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	if matches := dotPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	parts := strings.Split(filename, ".")
	if len(parts) > 1 {
		parts = parts[:len(parts)-1]
	}
	return strings.Join(parts, " "), 0
}
