package metadata

import (
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// MinYear — нижняя граница допустимого года выпуска (год первого фильма).
const MinYear = 1888

// maxYearOffset — сколько лет вперёд от текущего года допускается
// (анонсы выходят заранее, но не на десятилетия).
const maxYearOffset = 2

var (
	// S01E01 / s01e01 / S01.E01 (регистронезависимо); разделитель перед
	// маркером сезона — точка или пробел, чтобы ловить "Show (2020) S01E01".
	episodePattern = regexp.MustCompile(`(?i)^(.+)[.\s]S(\d{2})\.?E(\d{2})(?:\..+)?$`)
	// 1x01 / 12x345 (регистронезависимо).
	xEpisodePattern = regexp.MustCompile(`(?i)^(.+?)\.(\d{1,2})x(\d{1,3})(?:\..+)?$`)
	parenPattern    = regexp.MustCompile(`(?i)^(.+?)\s*\((\d{4})\)(?:\.[^.]+)?$`)
	dotPattern      = regexp.MustCompile(`(?i)^(.+)\.(\d{4})(?:\.[^.]+)?$`)
	// Год через пробел после названия, без точек и скобок: "The Matrix 1999".
	trailingYearPattern = regexp.MustCompile(`(?i)^(.+?)\s+(\d{4})$`)
	// Год в скобках в конце названия сериала ("Show (2020) S01E01").
	trailingParenYearPattern = regexp.MustCompile(`(?i)\s*\(\d{4}\)\s*$`)
)

// ParseFilename parses a filename (without directory path) to extract title and year.
func ParseFilename(filename string) (string, int) {
	// Episode patterns must come before year patterns:
	// "Show Name (2020) S01E01.mkv" should be parsed as TV show,
	// not as a movie with year 2020.
	if matches := episodePattern.FindStringSubmatch(filename); matches != nil {
		return normalizeEpisodeTitle(matches[1]), 0
	}

	// Формат "1x01": "Show.1x01.Title.mkv" → сезон 1, серия 1.
	if matches := xEpisodePattern.FindStringSubmatch(filename); matches != nil {
		return normalizeEpisodeTitle(matches[1]), 0
	}

	// Parenthesized year: "Movie Name (2020).mkv" → title "Movie Name", year 2020
	if matches := parenPattern.FindStringSubmatch(filename); matches != nil {
		title := normalizeTitle(matches[1])
		return title, validYear(matches[2])
	}

	// Dot-separated year: "The.Matrix.1999.mkv" → title "The Matrix", year 1999
	if matches := dotPattern.FindStringSubmatch(filename); matches != nil {
		title := normalizeTitle(matches[1])
		return title, validYear(matches[2])
	}

	// Год через пробел в конце базового имени (без расширения):
	// "The Matrix 1999.mkv" → title "The Matrix", year 1999.
	base := strings.TrimSuffix(filename, filepath.Ext(filename))
	if matches := trailingYearPattern.FindStringSubmatch(base); matches != nil {
		title := normalizeTitle(matches[1])
		return title, validYear(matches[2])
	}

	parts := strings.Split(base, ".")
	if len(parts) > 1 {
		parts = parts[:len(parts)-1]
	}
	return strings.TrimSpace(parts[0]), 0
}

// normalizeTitle заменяет точки на пробелы и убирает лишние пробелы —
// единая нормализация title для всех веток парсинга.
func normalizeTitle(title string) string {
	return strings.TrimSpace(strings.ReplaceAll(title, ".", " "))
}

// normalizeEpisodeTitle нормализует название сериала и убирает хвостовой
// год в скобках, который относится к дате сериала, а не к названию.
func normalizeEpisodeTitle(title string) string {
	title = normalizeTitle(title)
	return strings.TrimSpace(trailingParenYearPattern.ReplaceAllString(title, ""))
}

// validYear валидирует год по диапазону (1888..текущий+2).
// Некорректные и невероятные значения превращаются в 0.
func validYear(s string) int {
	year, err := strconv.Atoi(s)
	if err != nil || !IsValidYear(year) {
		return 0
	}
	return year
}

// IsValidYear проверяет, попадает ли год в допустимый диапазон.
func IsValidYear(year int) bool {
	return year >= MinYear && year <= time.Now().Year()+maxYearOffset
}
