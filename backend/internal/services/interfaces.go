package services

import (
	"context"

	"github.com/gofiber/fiber/v2"
)

// JWTService defines the interface for JWT token operations.
type JWTService interface {
	GenerateToken(userID uint, email string) (string, error)
	ValidateToken(tokenString string) (*Claims, error)
}

// OTPStoreInterface defines the interface for OTP code operations.
type OTPStoreInterface interface {
	Generate(addr string) (string, error)
	Verify(email, code string) bool
	Stop()
}

// ScannerInterface defines the interface for library scanning operations.
type ScannerInterface interface {
	ScanLibrary(ctx context.Context, libraryID uint) error
	ScanAll(ctx context.Context) error
	GetScanStatus(libraryID uint) *ScanStatus
}

// ScanStatus represents the current state of a library scan.
type ScanStatus struct {
	LibraryID uint   `json:"library_id"`
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
