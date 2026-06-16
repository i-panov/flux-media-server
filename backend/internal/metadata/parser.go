package metadata

import (
	"regexp"
	"strconv"
	"strings"
)

var (
	dotPattern      = regexp.MustCompile(`^(.+)\.(\d{4})\.[^.]+$`)
	parenPattern    = regexp.MustCompile(`^(.+)\s*\((\d{4})\)\.[^.]+$`)
	episodePattern  = regexp.MustCompile(`^(.+)\.S(\d{2})E(\d{2})\..+$`)
)

func ParseFilename(filename string) (string, int) {
	if matches := dotPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	if matches := parenPattern.FindStringSubmatch(filename); matches != nil {
		title := strings.TrimSpace(matches[1])
		year, _ := strconv.Atoi(matches[2])
		return title, year
	}

	if matches := episodePattern.FindStringSubmatch(filename); matches != nil {
		title := strings.ReplaceAll(matches[1], ".", " ")
		return title, 0
	}

	parts := strings.Split(filename, ".")
	if len(parts) > 1 {
		parts = parts[:len(parts)-1]
	}
	return strings.Join(parts, " "), 0
}
