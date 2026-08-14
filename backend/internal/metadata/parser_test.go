package metadata

import (
	"testing"

	"github.com/stretchr/testify/assert"
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
