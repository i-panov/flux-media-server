package config

import (
	"os"

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
	Host  string `yaml:"host"`
	Port  int    `yaml:"port"`
	Debug bool   `yaml:"debug"`
}

type DatabaseConfig struct {
	Path string `yaml:"path"`
}

type AuthConfig struct {
	JWTSecret        string     `yaml:"jwt_secret"`
	CodeLength       int        `yaml:"code_length"`
	CodeExpiry       int        `yaml:"code_expiry"`
	AllowedEmails    []string   `yaml:"allowed_emails"`
	AllowUnknownEmail bool      `yaml:"allow_unknown_email"`
	SMTP             SMTPConfig `yaml:"smtp"`
}

type SMTPConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
}

type ScannerConfig struct {
	Enabled  bool `yaml:"enabled"`
	Interval int  `yaml:"interval"`
}

type MediaConfig struct {
	ThumbnailPath     string   `yaml:"thumbnail_path"`
	AllowedExtensions []string `yaml:"allowed_extensions"`
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
	if cfg.Auth.CodeLength == 0 {
		cfg.Auth.CodeLength = 6
	}
	if cfg.Auth.CodeExpiry == 0 {
		cfg.Auth.CodeExpiry = 300
	}

	return cfg, nil
}
