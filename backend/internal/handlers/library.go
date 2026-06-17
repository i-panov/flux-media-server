package handlers

import (
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

type LibraryHandler struct {
	libraryRepo *repository.LibraryRepository
	scanner     *services.ScannerService
}

func NewLibraryHandler(libraryRepo *repository.LibraryRepository, scanner *services.ScannerService) *LibraryHandler {
	return &LibraryHandler{
		libraryRepo: libraryRepo,
		scanner:     scanner,
	}
}

type CreateLibraryRequest struct {
	Name         string `json:"name"`
	Path         string `json:"path"`
	Type         string `json:"type"`
	ScanInterval int    `json:"scan_interval"`
}

func (h *LibraryHandler) List(c *fiber.Ctx) error {
	libraries, err := h.libraryRepo.FindAll()
	if err != nil {
		log.Printf("FindAll: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch libraries",
		})
	}

	return c.JSON(libraries)
}

func (h *LibraryHandler) Create(c *fiber.Ctx) error {
	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.Name == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Name is required",
		})
	}
	if req.Path == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Path is required",
		})
	}

	library := &models.MediaLibrary{
		Name:         req.Name,
		Path:         req.Path,
		Type:         req.Type,
		Enabled:      true,
		ScanInterval: req.ScanInterval,
	}

	if err := h.libraryRepo.Create(library); err != nil {
		log.Printf("Create: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to create library",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(library)
}

func (h *LibraryHandler) Update(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	library, err := h.libraryRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Library not found",
		})
	}

	var req CreateLibraryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	if req.Name == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Name is required",
		})
	}
	if req.Path == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Path is required",
		})
	}

	library.Name = req.Name
	library.Path = req.Path
	library.Type = req.Type
	library.ScanInterval = req.ScanInterval

	if err := h.libraryRepo.Update(library); err != nil {
		log.Printf("Update: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update library",
		})
	}

	return c.JSON(library)
}

func (h *LibraryHandler) Delete(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	if err := h.libraryRepo.Delete(uint(id)); err != nil {
		log.Printf("Delete: %v", err)
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete library",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Library deleted successfully",
	})
}

func (h *LibraryHandler) Scan(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid library ID",
		})
	}

	library, err := h.libraryRepo.FindByID(uint(id))
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "Library not found",
		})
	}

	go func() {
		if err := h.scanner.ScanLibrary(library); err != nil {
			log.Printf("Error scanning library %s: %v", library.Name, err)
		}
	}()

	return c.JSON(fiber.Map{
		"message": "Scan started",
	})
}
