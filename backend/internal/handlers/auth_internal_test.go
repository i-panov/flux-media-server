package handlers

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNormalizeDeviceID(t *testing.T) {
	for _, valid := range []string{
		"",
		"550e8400-e29b-41d4-a716-446655440000",
		"abc_DEF-123.4:5",
		strings.Repeat("a", maxDeviceIDLength),
	} {
		got, err := normalizeDeviceID("  " + valid + "  ")
		require.NoError(t, err, valid)
		assert.Equal(t, valid, got)
	}

	for _, invalid := range []string{
		"has space",
		"sl/ash",
		"back\\slash",
		"кириллица",
		strings.Repeat("a", maxDeviceIDLength+1),
	} {
		_, err := normalizeDeviceID(invalid)
		assert.ErrorIs(t, err, ErrInvalidDeviceID, invalid)
	}
}
