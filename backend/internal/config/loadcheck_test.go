package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

// TestLoadRealConfigFiles проверяет, что реальные файлы конфигурации проходят
// KnownFields-валидацию (в них нет неизвестных полей). config.example.yaml
// в не-debug режиме падает на проверке секрета (это ожидаемо) — важно, что
// ошибка не про неизвестное поле.
func TestLoadRealConfigFiles(t *testing.T) {
	wd, err := os.Getwd()
	require.NoError(t, err)

	full := filepath.Join(wd, "..", "..", "configs", "config.yaml")
	if _, err := os.Stat(full); err != nil {
		t.Skip("config.yaml not present")
	}
	cfg, err := Load(full)
	require.NoError(t, err, "Load(config.yaml) must succeed")
	require.NotZero(t, cfg.Server.Port)

	example := filepath.Join(wd, "..", "..", "configs", "config.example.yaml")
	_, err = Load(example)
	require.Error(t, err, "example config (non-debug, change-me secret) must be rejected")
	require.NotContains(t, err.Error(), "not found in type", "example config must not contain unknown fields")
	require.True(t, strings.Contains(err.Error(), "jwt_secret"))
}
