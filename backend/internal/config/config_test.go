package config

import (
	"os"
	"path/filepath"
	"strconv"
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
  env: "dev"
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
	assert.Equal(t, "dev", cfg.Server.Env)
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
	assert.Equal(t, "production", cfg.Server.Env)
	assert.Equal(t, 6, cfg.Auth.CodeLength)
	assert.Equal(t, 300, cfg.Auth.CodeExpiry)
	assert.Equal(t, 1, cfg.Auth.JWTExpiry)
	assert.Equal(t, 10000, cfg.Auth.MaxOTPEntries)
}

func TestLoadConfigShortSecret(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
database:
  path: "./test.db"
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

func TestLoadConfigEmptyDatabasePath(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	_, err = Load(configPath)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "database.path")
}

func TestLoadConfigMemoryDatabaseAllowed(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
database:
  path: ":memory:"
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	_, err = Load(configPath)
	assert.NoError(t, err)
}

func TestLoadConfigInvalidValues(t *testing.T) {
	cases := []struct {
		name    string
		yaml    string
		errPart string
	}{
		{
			name:    "port too large",
			yaml:    "server:\n  port: 70000\n",
			errPart: "server.port",
		},
		{
			name:    "port negative",
			yaml:    "server:\n  port: -1\n",
			errPart: "server.port",
		},
		{
			name:    "negative max_upload_size",
			yaml:    "server:\n  max_upload_size: -5\n",
			errPart: "server.max_upload_size",
		},
		{
			name:    "code_length too small",
			yaml:    "auth:\n  code_length: 3\n  jwt_secret: \"test-secret-that-is-at-least-32-chars\"\n",
			errPart: "auth.code_length",
		},
		{
			name:    "code_length too large",
			yaml:    "auth:\n  code_length: 13\n  jwt_secret: \"test-secret-that-is-at-least-32-chars\"\n",
			errPart: "auth.code_length",
		},
		{
			name:    "negative jwt_expiry",
			yaml:    "auth:\n  jwt_expiry: -1\n  jwt_secret: \"test-secret-that-is-at-least-32-chars\"\n",
			errPart: "auth.jwt_expiry",
		},
		{
			name:    "negative rate_limiter.max",
			yaml:    "rate_limiter:\n  max: -1\n",
			errPart: "rate_limiter.max",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			configPath := filepath.Join(tmpDir, "config.yaml")
			content := "database:\n  path: \"./test.db\"\n" + tc.yaml
			err := os.WriteFile(configPath, []byte(content), 0644)
			require.NoError(t, err)

			_, err = Load(configPath)
			assert.Error(t, err)
			assert.Contains(t, err.Error(), tc.errPart)
		})
	}
}

func TestLoadConfigEnvOverrides(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.yaml")

	yamlContent := `
database:
  path: "./test.db"
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
  smtp:
    password: "yaml-pass"
`
	err := os.WriteFile(configPath, []byte(yamlContent), 0644)
	require.NoError(t, err)

	t.Setenv("FLUX_JWT_SECRET", "env-secret-that-is-also-at-least-32-chars")
	t.Setenv("FLUX_SMTP_PASSWORD", "env-pass")

	cfg, err := Load(configPath)
	require.NoError(t, err)
	assert.Equal(t, "env-secret-that-is-also-at-least-32-chars", cfg.Auth.JWTSecret)
	assert.Equal(t, "env-pass", cfg.Auth.SMTP.Password)
}

func TestLoadConfigEnvShortSecretRejected(t *testing.T) {
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

	t.Setenv("FLUX_JWT_SECRET", "short")

	_, err = Load(configPath)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "jwt_secret must be at least 32 characters")
}

func TestLoadConfigCORSValidation(t *testing.T) {
	base := `
database:
  path: "./test.db"
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
`

	write := func(t *testing.T, origins string) string {
		t.Helper()
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "config.yaml")
		content := base
		if origins != "" {
			content = "server:\n  cors_origins: \"" + origins + "\"\n" + content
		}
		err := os.WriteFile(configPath, []byte(content), 0644)
		require.NoError(t, err)
		return configPath
	}

	t.Run("wildcard with specific origins rejected", func(t *testing.T) {
		_, err := Load(write(t, "*, https://x.com"))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "cors_origins")
	})

	t.Run("wildcard alone allowed", func(t *testing.T) {
		_, err := Load(write(t, "*"))
		assert.NoError(t, err)
	})

	t.Run("specific origins allowed", func(t *testing.T) {
		_, err := Load(write(t, "https://a.com, https://b.com"))
		assert.NoError(t, err)
	})

	t.Run("empty means wildcard", func(t *testing.T) {
		_, err := Load(write(t, ""))
		assert.NoError(t, err)
	})
}

func TestLoadConfigDebugRequiresDevEnv(t *testing.T) {
	write := func(t *testing.T, debug bool, env string) string {
		t.Helper()
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "config.yaml")
		envLine := ""
		if env != "" {
			envLine = "  env: \"" + env + "\"\n"
		}
		content := "server:\n" + envLine + "  debug: " + strconv.FormatBool(debug) + "\n"
		content += `
database:
  path: "./test.db"
auth:
  jwt_secret: "test-secret-that-is-at-least-32-chars"
`
		err := os.WriteFile(configPath, []byte(content), 0644)
		require.NoError(t, err)
		return configPath
	}

	t.Run("debug without env rejected", func(t *testing.T) {
		_, err := Load(write(t, true, ""))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "debug")
	})

	t.Run("debug with production env rejected", func(t *testing.T) {
		_, err := Load(write(t, true, "production"))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "debug")
	})

	t.Run("debug with dev env allowed", func(t *testing.T) {
		_, err := Load(write(t, true, "dev"))
		assert.NoError(t, err)
	})

	t.Run("no debug allowed", func(t *testing.T) {
		_, err := Load(write(t, false, ""))
		assert.NoError(t, err)
	})
}
