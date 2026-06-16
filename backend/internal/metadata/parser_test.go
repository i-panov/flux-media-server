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
	}

	for _, tt := range tests {
		t.Run(tt.filename, func(t *testing.T) {
			title, year := ParseFilename(tt.filename)
			assert.Equal(t, tt.title, title)
			assert.Equal(t, tt.year, year)
		})
	}
}
