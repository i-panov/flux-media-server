//go:build unix

package services

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDiskFreeBytesUnix(t *testing.T) {
	free := diskFreeBytes(t.TempDir())
	assert.Greater(t, free, int64(0))

	// need <= 0 и пропуски — без ошибки.
	require.NoError(t, checkDiskSpace(t.TempDir(), 0))
	require.NoError(t, checkDiskSpace(t.TempDir(), -5))
	// Заведомо больше, чем есть, — ошибка.
	require.Error(t, checkDiskSpace(t.TempDir(), free+1))
}
