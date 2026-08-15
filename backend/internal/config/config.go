package config

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"strings"

	"flux/internal/models"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server      ServerConfig      `yaml:"server"`
	Database    DatabaseConfig    `yaml:"database"`
	Auth        AuthConfig        `yaml:"auth"`
	Scanner     ScannerConfig     `yaml:"scanner"`
	RateLimiter RateLimiterConfig `yaml:"rate_limiter"`
	Media       MediaConfig       `yaml:"media"`
}

type ServerConfig struct {
	Host          string `yaml:"host"`
	Port          int    `yaml:"port"`
	Debug         bool   `yaml:"debug"`
	Env           string `yaml:"env"` // "dev" | "production" (default)
	CORSOrigins   string `yaml:"cors_origins"`
	MaxUploadSize int64  `yaml:"max_upload_size"`
}

type DatabaseConfig struct {
	Path string `yaml:"path"`
}

type AuthConfig struct {
	JWTSecret         string     `yaml:"jwt_secret"`
	JWTExpiry         int        `yaml:"jwt_expiry"`     // in hours
	RefreshExpiry     int        `yaml:"refresh_expiry"` // in hours
	CodeLength        int        `yaml:"code_length"`
	CodeExpiry        int        `yaml:"code_expiry"`
	MaxOTPEntries     int        `yaml:"max_otp_entries"`
	AllowedEmails     []string   `yaml:"allowed_emails"`
	AllowUnknownEmail bool       `yaml:"allow_unknown_email"`
	SMTP              SMTPConfig `yaml:"smtp"`
}

type SMTPConfig struct {
	Host        string `yaml:"host"`
	Port        int    `yaml:"port"`
	Username    string `yaml:"username"`
	Password    string `yaml:"password"`
	From        string `yaml:"from"`
	RequireTLS  bool   `yaml:"require_tls"`
	ImplicitTLS bool   `yaml:"implicit_tls"`
}

type ScannerConfig struct {
	Enabled      bool `yaml:"enabled"`
	Interval     int  `yaml:"interval"`
	WatchEnabled bool `yaml:"watch_enabled"`
}

type RateLimiterConfig struct {
	Max        int   `yaml:"max"`
	Expiration int64 `yaml:"expiration"` // in seconds
}

type MediaConfig struct {
	ThumbnailPath string `yaml:"thumbnail_path"`
	VideoPath     string `yaml:"video_path"`
	AudioPath     string `yaml:"audio_path"`
}

// MediaPath represents a scan path with its media type.
type MediaPath struct {
	Path string
	Type models.MediaType // "video" or "audio"
}

// MediaPaths returns all configured media paths with their types.
func (m MediaConfig) MediaPaths() []MediaPath {
	return []MediaPath{
		{Path: m.VideoPath, Type: models.MediaTypeVideo},
		{Path: m.AudioPath, Type: models.MediaTypeAudio},
	}
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	// KnownFields(true) отклоняет неизвестные поля конфига — опечатка в
	// ключе YAML не останется незамеченной (молча игнорируемой).
	cfg := &Config{}
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(cfg); err != nil {
		return nil, err
	}

	// Чувствительные поля можно задать через окружение: env имеет
	// приоритет над YAML, чтобы секреты не лежали в открытом конфиге.
	if v := os.Getenv("FLUX_JWT_SECRET"); v != "" {
		cfg.Auth.JWTSecret = v
	}
	if v := os.Getenv("FLUX_SMTP_PASSWORD"); v != "" {
		cfg.Auth.SMTP.Password = v
	}

	// Set defaults
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Server.Env == "" {
		cfg.Server.Env = "production"
	}
	if cfg.Server.MaxUploadSize == 0 {
		cfg.Server.MaxUploadSize = 100 * 1024 * 1024 // 100MB
	}
	if cfg.Auth.CodeLength == 0 {
		cfg.Auth.CodeLength = 6
	}
	if cfg.Auth.CodeExpiry == 0 {
		cfg.Auth.CodeExpiry = 300
	}
	if cfg.Auth.JWTExpiry == 0 {
		cfg.Auth.JWTExpiry = 1
	}
	if cfg.Auth.RefreshExpiry == 0 {
		cfg.Auth.RefreshExpiry = 720 // 30 days
	}
	if cfg.Auth.MaxOTPEntries == 0 {
		cfg.Auth.MaxOTPEntries = 10000
	}
	if cfg.RateLimiter.Max == 0 {
		cfg.RateLimiter.Max = 10
	}
	if cfg.RateLimiter.Expiration == 0 {
		cfg.RateLimiter.Expiration = 60
	}

	// Validation
	if cfg.Database.Path == "" {
		return nil, errors.New("database.path must not be empty (use ':memory:' only for tests)")
	}
	if cfg.Server.Port < 1 || cfg.Server.Port > 65535 {
		return nil, fmt.Errorf("server.port must be between 1 and 65535, got %d", cfg.Server.Port)
	}
	if cfg.Server.MaxUploadSize <= 0 {
		return nil, fmt.Errorf("server.max_upload_size must be > 0, got %d", cfg.Server.MaxUploadSize)
	}
	if cfg.Auth.CodeLength < 4 || cfg.Auth.CodeLength > 12 {
		return nil, fmt.Errorf("auth.code_length must be between 4 and 12, got %d", cfg.Auth.CodeLength)
	}
	if cfg.Auth.JWTExpiry <= 0 {
		return nil, fmt.Errorf("auth.jwt_expiry must be > 0, got %d", cfg.Auth.JWTExpiry)
	}
	if cfg.RateLimiter.Max <= 0 {
		return nil, fmt.Errorf("rate_limiter.max must be > 0, got %d", cfg.RateLimiter.Max)
	}

	// "*" нельзя комбинировать с конкретными origins: браузеры в этом
	// случае игнорируют Access-Control-Allow-Origin, а Allow-Credentials
	// с wildcard запрещён спецификацией.
	if err := validateCORS(cfg.Server.CORSOrigins); err != nil {
		return nil, err
	}

	// Debug-режим возвращает OTP-коды в ответах API и пишет SQL с
	// секретами — запускать его вне локальной разработки нельзя.
	if cfg.Server.Debug && cfg.Server.Env != "dev" {
		return nil, errors.New("server.debug is enabled but server.env is not \"dev\": debug mode is only allowed in development")
	}

	// Validate JWT secret
	if len(cfg.Auth.JWTSecret) < 32 {
		return nil, errors.New("jwt_secret must be at least 32 characters")
	}

	// Refuse to run in production mode with the well-known default secret.
	if !cfg.Server.Debug && strings.HasPrefix(cfg.Auth.JWTSecret, "change-me") {
		return nil, errors.New("jwt_secret must be changed from the default value (generate one with: openssl rand -base64 48)")
	}

	return cfg, nil
}

func validateCORS(origins string) error {
	if origins == "" || origins == "*" {
		return nil
	}
	for _, o := range strings.Split(origins, ",") {
		if strings.TrimSpace(o) == "*" {
			return errors.New("server.cors_origins cannot combine \"*\" with specific origins")
		}
	}
	return nil
}
