package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfig(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  host: "127.0.0.1"
  port: 9090
  debug: true

database:
  path: "./test.db"

auth:
  jwt_secret: "test-secret"
  code_length: 6
  code_expiry: 300
  allowed_emails:
    - test@example.com
  allow_unknown_email: false
  smtp:
    host: "smtp.test.com"
    port: 587
    username: "test@test.com"
    password: "test-pass"
    from: "Test <test@test.com>"

scanner:
  enabled: true
  interval: 30

media:
  thumbnail_path: "./thumbnails"
  allowed_extensions:
    - .mp4
    - .mkv
`
	os.WriteFile(configPath, []byte(yamlContent), 0644)

	cfg, err := Load(configPath)
	assert.NoError(t, err)
	assert.Equal(t, "127.0.0.1", cfg.Server.Host)
	assert.Equal(t, 9090, cfg.Server.Port)
	assert.Equal(t, true, cfg.Server.Debug)
	assert.Equal(t, "./test.db", cfg.Database.Path)
	assert.Equal(t, "test-secret", cfg.Auth.JWTSecret)
	assert.Equal(t, []string{"test@example.com"}, cfg.Auth.AllowedEmails)
	assert.Equal(t, false, cfg.Auth.AllowUnknownEmail)
}
