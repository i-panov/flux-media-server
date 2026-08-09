package config

import (
	"errors"
	"os"
	"strings"

	"flux/internal/models"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	Auth     AuthConfig     `yaml:"auth"`
	Scanner  ScannerConfig  `yaml:"scanner"`
	Media    MediaConfig    `yaml:"media"`
}

type ServerConfig struct {
	Host          string `yaml:"host"`
	Port          int    `yaml:"port"`
	Debug         bool   `yaml:"debug"`
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

	cfg := &Config{}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	// Set defaults
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
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

	// Validate code length
	if cfg.Auth.CodeLength < 6 {
		return nil, errors.New("auth.code_length must be >= 6")
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
