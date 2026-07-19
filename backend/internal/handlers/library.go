package handlers

import (
	"context"
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type LibraryHandler struct {
	libraryRepo repository.LibraryRepository
	scanner     services.ScannerInterface
	watcher     services.WatcherInterface
}

func NewLibraryHandler(libraryRepo repository.LibraryRepository, scanner services.ScannerInterface, watcher services.WatcherInterface) *LibraryHandler {
	return &LibraryHandler{
		libraryRepo: libraryRepo,
		scanner:     scanner,
		watcher:     watcher,
	}
}

type CreateLibraryRequest struct {
	Name         string `json:"name"`
	Path         string `json:"path"`
	Type         string `json:"type"`
	ScanInterval int    `json:"scan_interval"`
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

	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}
	if req.Path == "" {
		return response.Error(c, fiber.StatusBadRequest, "Path is required")
	}

	library := &models.MediaLibrary{
		Name:         req.Name,
		Path:         req.Path,
		Type:         req.Type,
		Enabled:      true,
		ScanInterval: req.ScanInterval,
	}

	ctx := c.UserContext()
	if err := h.libraryRepo.Create(ctx, library); err != nil {
		log.Printf("Create: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create library")
	}

	// Start watching this library path.
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

	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}
	if req.Path == "" {
		return response.Error(c, fiber.StatusBadRequest, "Path is required")
	}

	library.Name = req.Name
	library.Path = req.Path
	library.Type = req.Type
	library.ScanInterval = req.ScanInterval

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

	go func() {
		scanCtx := context.Background()
		if err := h.scanner.ScanLibrary(scanCtx, library.ID); err != nil {
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
