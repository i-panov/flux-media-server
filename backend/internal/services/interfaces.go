package services

import (
	"context"

	"github.com/gofiber/fiber/v2"
)

// JWTService defines the interface for JWT token operations.
type JWTService interface {
	GenerateToken(userID uint, email string) (string, error)
	GenerateRefreshToken(userID uint, email string) (string, error)
	GenerateTokenPair(userID uint, email string) (*TokenPair, error)
	ValidateToken(tokenString string) (*Claims, error)
	ValidateRefreshToken(tokenString string) (*Claims, error)
}

// OTPStoreInterface defines the interface for OTP code operations.
type OTPStoreInterface interface {
	Generate(addr string) (string, error)
	Verify(email, code string) bool
	Stop()
}

// ScannerInterface defines the interface for scanning operations.
type ScannerInterface interface {
	ScanPath(ctx context.Context, path, mediaType string) error
	ScanAll(ctx context.Context) error
	GetScanStatus(key string) *ScanStatus
}

// ScanStatus represents the current state of a scan.
type ScanStatus struct {
	Running   bool   `json:"running"`
	StartedAt string `json:"started_at,omitempty"`
	Error     string `json:"last_error,omitempty"`
}

// StreamerInterface defines the interface for file streaming operations.
type StreamerInterface interface {
	IsPathAllowed(ctx context.Context, filePath string) (bool, error)
	Stream(c *fiber.Ctx, filePath string) error
}

// WatcherInterface defines the interface for file system watching operations.
type WatcherInterface interface {
	StartWithPaths(paths []string) error
	AddPath(path string)
	RemovePath(path string)
	Stop()
}
