package handlers

import (
	"context"
	"errors"
	"log"
	"os"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type LibraryHandler struct {
	libraryRepo repository.LibraryRepository
	scanner     services.ScannerInterface
	watcher     services.WatcherInterface
	config      *config.Config
}

func NewLibraryHandler(libraryRepo repository.LibraryRepository, scanner services.ScannerInterface, watcher services.WatcherInterface, cfg *config.Config) *LibraryHandler {
	return &LibraryHandler{
		libraryRepo: libraryRepo,
		scanner:     scanner,
		watcher:     watcher,
		config:      cfg,
	}
}

type CreateLibraryRequest struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

func (h *LibraryHandler) List(c *fiber.Ctx) error {
	ctx := c.UserContext()
	libraries, err := h.libraryRepo.FindAll(ctx)
	if err != nil {
		log.Printf("FindAll: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch libraries")
	}

	return c.JSON(libraries)
}

func (h *LibraryHandler) Create(c *fiber.Ctx) error {
	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}

	req.Type = strings.ToLower(strings.TrimSpace(req.Type))
	if req.Type != "video" && req.Type != "audio" {
		return response.Error(c, fiber.StatusBadRequest, "Type must be 'video' or 'audio'")
	}

	// Generate path from config based on type, validating the name to
	// prevent path traversal outside the media base directory.
	libPath, err := h.libraryPath(req.Type, req.Name)
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid library name")
	}

	library := &models.MediaLibrary{
		Name:    req.Name,
		Path:    libPath,
		Type:    req.Type,
		Enabled: true,
	}

	ctx := c.UserContext()
	if err := h.libraryRepo.Create(ctx, library); err != nil {
		log.Printf("Create: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create library")
	}

	// Create the directory and start watching.
	os.MkdirAll(libPath, 0755)
	if h.watcher != nil {
		h.watcher.AddPath(library.Path)
	}

	return c.Status(fiber.StatusCreated).JSON(library)
}

func (h *LibraryHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid library ID")
	}

	ctx := c.UserContext()
	library, err := h.libraryRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Library not found")
	}

	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	nameChanged := false
	if req.Name != "" {
		library.Name = strings.TrimSpace(req.Name)
		nameChanged = true
	}
	if req.Type != "" {
		newType := strings.ToLower(strings.TrimSpace(req.Type))
		if newType != "video" && newType != "audio" {
			return response.Error(c, fiber.StatusBadRequest, "Type must be 'video' or 'audio'")
		}
		library.Type = newType
		nameChanged = true
	}
	if nameChanged {
		libPath, err := h.libraryPath(library.Type, library.Name)
		if err != nil {
			return response.Error(c, fiber.StatusBadRequest, "Invalid library name")
		}
		library.Path = libPath
	}

	if err := h.libraryRepo.Update(ctx, library); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update library")
	}

	return c.JSON(library)
}

func (h *LibraryHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid library ID")
	}

	ctx := c.UserContext()

	// Get library before deleting to know the path for watcher.
	library, err := h.libraryRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Library not found")
	}

	if err := h.libraryRepo.Delete(ctx, uint(id)); err != nil {
		log.Printf("Delete: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete library")
	}

	// Stop watching this library path.
	if h.watcher != nil {
		h.watcher.RemovePath(library.Path)
	}

	return c.JSON(fiber.Map{"message": "Library deleted successfully"})
}

func (h *LibraryHandler) Scan(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid library ID")
	}

	ctx := c.UserContext()
	library, err := h.libraryRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Library not found")
	}

	// Start the scan synchronously in a goroutine, but report conflicts.
	go func() {
		scanCtx := context.Background()
		if err := h.scanner.ScanLibrary(scanCtx, library.ID); err != nil {
			if errors.Is(err, services.ErrScanInProgress) {
				return // another scan is already running, nothing to log
			}
			log.Printf("Error scanning library %s: %v", library.Name, err)
		} else {
			log.Printf("Scan completed for library %s", library.Name)
		}
	}()

	return c.JSON(fiber.Map{"message": "Scan started"})
}

// ScanStatus returns the current scan status for a library.
func (h *LibraryHandler) ScanStatus(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid library ID")
	}

	status := h.scanner.GetScanStatus(uint(id))
	return c.JSON(status)
}

// libraryPath builds a library directory path from its type and name,
// ensuring the result stays inside the configured media base directory.
func (h *LibraryHandler) libraryPath(libType, name string) (string, error) {
	basePath := h.config.Media.VideoPath
	if libType == "audio" {
		basePath = h.config.Media.AudioPath
	}
	return services.LibraryPathFromName(basePath, name)
}
