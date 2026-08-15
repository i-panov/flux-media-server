package metadata

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseFilename(t *testing.T) {
	tests := []struct {
		filename string
		title    string
		year     int
	}{
		{"The.Matrix.1999.mkv", "The Matrix", 1999},
		{"Inception (2010).mp4", "Inception", 2010},
		{"Breaking.Bad.S01E01.Pilot.mkv", "Breaking Bad", 0},
		{"Movie Name (2024).avi", "Movie Name", 2024},
		// Формат 1x01: сезон 1, серия 1.
		{"Show.1x01.Title.mkv", "Show", 0},
		// Строчные s01e01.
		{"show.name.s01e01.title.mkv", "show name", 0},
		// S01.E01 с точкой между сезоном и серией.
		{"Show.Name.S01.E01.mkv", "Show Name", 0},
		// Год через пробел, без точек и скобок.
		{"The Matrix 1999.mkv", "The Matrix", 1999},
		// Эпизод с годом в скобках — парсится как сериал, год уходит из названия.
		{"Show Name (2020) S01E01.mkv", "Show Name", 0},
		// Год вне допустимого диапазона → 0.
		{"The Movie 1500.mkv", "The Movie", 0},
		{"Movie (1800).avi", "Movie", 0},
		// Файл без расширения.
		{"The Matrix 1999", "The Matrix", 1999},
		// Точки без года: fallback не должен терять название.
		{"The.Matrix.mkv", "The Matrix", 0},
		{"Show.Name.1080p.mkv", "Show Name 1080p", 0},
		// Кириллица.
		{"Фильм.2024.mkv", "Фильм", 2024},
		{"Кино.Без.Года.mkv", "Кино Без Года", 0},
		{"Игра (2014).mkv", "Игра", 2014},
		// S1E01 / S01E1 — короткие сезон и серия.
		{"Show.S1E01.mkv", "Show", 0},
		{"Show.S01E1.mkv", "Show", 0},
		{"Series.Name.S1E1.720p.mkv", "Series Name", 0},
		// Несколько сегментов после года.
		{"Interstellar.2014.1080p.BluRay.mkv", "Interstellar", 2014},
		{"Movie (2020).1080p.BluRay.mkv", "Movie", 2020},
		{"Title.2021.2160p.WEB-DL.mkv", "Title", 2021},
		// Пустая строка.
		{"", "", 0},
		{"   ", "", 0},
		// Скобки без расширения.
		{"Movie (2020)", "Movie", 2020},
	}

	for _, tt := range tests {
		t.Run(tt.filename, func(t *testing.T) {
			title, year := ParseFilename(tt.filename)
			assert.Equal(t, tt.title, title)
			assert.Equal(t, tt.year, year)
		})
	}
}

func TestIsValidYear(t *testing.T) {
	assert.True(t, IsValidYear(1888))
	assert.True(t, IsValidYear(1999))
	assert.False(t, IsValidYear(1887))
	assert.False(t, IsValidYear(0))
	assert.False(t, IsValidYear(-1))
}

func TestIsValidYearAt(t *testing.T) {
	now := mustTime(t, "2030-01-01T00:00:00Z")
	assert.True(t, IsValidYearAt(1888, now))
	assert.True(t, IsValidYearAt(2032, now))
	assert.False(t, IsValidYearAt(2033, now))
	assert.False(t, IsValidYearAt(1887, now))
}

func mustTime(t *testing.T, s string) time.Time {
	t.Helper()
	tm, err := time.Parse(time.RFC3339, s)
	require.NoError(t, err)
	return tm
}
