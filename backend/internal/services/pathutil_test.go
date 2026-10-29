package services

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestValidateContentDirs(t *testing.T) {
	good := map[string]string{
		"video":     "/media/video",
		"audio":     "/media/audio",
		"originals": "/media/originals",
		"temp":      "/data/tmp",
	}
	assert.NoError(t, ValidateContentDirs(good))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video":     "/media/video",
		"originals": "/media/video",
	}))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video":     "/media",
		"originals": "/media/originals",
	}))

	assert.Error(t, ValidateContentDirs(map[string]string{
		"video": "/media/video",
		"temp":  "",
	}))
}
