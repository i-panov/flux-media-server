package config

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLoadConfig(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
server:
  host: "127.0.0.1"
  port: 9090
  debug: true
  cors_origins: "https://example.com"

database:
  path: "./test.db"

auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
  jwt_expiry: 48
  code_length: 8
  code_expiry: 600
  max_otp_entries: 5000
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
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	cfg, err := Load(configPath)
	assert.NoError(t, err)

	// Server
	assert.Equal(t, "127.0.0.1", cfg.Server.Host)
	assert.Equal(t, 9090, cfg.Server.Port)
	assert.True(t, cfg.Server.Debug)
	assert.Equal(t, "https://example.com", cfg.Server.CORSOrigins)

	// Database
	assert.Equal(t, "./test.db", cfg.Database.Path)

	// Auth
	assert.Equal(t, "test-secret-that-is-at-least-32-chars", cfg.Auth.JWTSecret)
	assert.Equal(t, 48, cfg.Auth.JWTExpiry)
	assert.Equal(t, 8, cfg.Auth.CodeLength)
	assert.Equal(t, 600, cfg.Auth.CodeExpiry)
	assert.Equal(t, 5000, cfg.Auth.MaxOTPEntries)
	assert.Equal(t, []string{"test@example.com"}, cfg.Auth.AllowedEmails)
	assert.False(t, cfg.Auth.AllowUnknownEmail)

	// SMTP
	assert.Equal(t, "smtp.test.com", cfg.Auth.SMTP.Host)
	assert.Equal(t, 587, cfg.Auth.SMTP.Port)
	assert.Equal(t, "test@test.com", cfg.Auth.SMTP.Username)
	assert.Equal(t, "Test <test@test.com>", cfg.Auth.SMTP.From)

	// Scanner
	assert.True(t, cfg.Scanner.Enabled)
	assert.Equal(t, 30, cfg.Scanner.Interval)

	// Media
	assert.Equal(t, "./thumbnails", cfg.Media.ThumbnailPath)
}

func TestLoadConfigDefaults(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
database:
  path: "./test.db"
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	cfg, err := Load(configPath)
	assert.NoError(t, err)

	assert.Equal(t, 8080, cfg.Server.Port)
	assert.Equal(t, 6, cfg.Auth.CodeLength)
	assert.Equal(t, 300, cfg.Auth.CodeExpiry)
	assert.Equal(t, 1, cfg.Auth.JWTExpiry)
	assert.Equal(t, 10000, cfg.Auth.MaxOTPEntries)
}

func TestLoadConfigShortSecret(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
auth:
  jwt_secret: "too-short"
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	_, err = Load(configPath)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "jwt_secret must be at least 32 characters")
}

func TestLoadConfigMissingFile(t *testing.T) {
	_, err := Load("/nonexistent/config.yaml")
	assert.Error(t, err)
}
