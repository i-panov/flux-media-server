package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type MaintenanceHandler struct {
	media repository.MediaRepository
	svc   *services.MediaMaintenanceService
}

func NewMaintenanceHandler(media repository.MediaRepository, svc *services.MediaMaintenanceService) *MaintenanceHandler {
	return &MaintenanceHandler{media: media, svc: svc}
}

func (h *MaintenanceHandler) Get(c *fiber.Ctx) error {
	missingThumbs, err := h.media.CountMissingThumbnails(c.UserContext())
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to count thumbnails")
	}
	missingCovers, err := h.media.CountMissingCovers(c.UserContext())
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to count covers")
	}
	return c.JSON(fiber.Map{
		"missing_thumbnails": missingThumbs,
		"missing_covers":     missingCovers,
		"state":              h.svc.Status(),
	})
}

func (h *MaintenanceHandler) BackfillThumbnails(c *fiber.Ctx) error {
	if !h.svc.StartThumbnails() {
		return response.Error(c, fiber.StatusConflict, "Maintenance already running")
	}
	return c.JSON(h.svc.Status())
}

func (h *MaintenanceHandler) BackfillCovers(c *fiber.Ctx) error {
	if !h.svc.StartCovers() {
		return response.Error(c, fiber.StatusConflict, "Maintenance already running")
	}
	return c.JSON(h.svc.Status())
}
