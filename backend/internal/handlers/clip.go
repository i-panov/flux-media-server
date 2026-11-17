package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type ClipHandler struct {
	clips   *repository.ClipStore
	service *services.ClipService
}

func NewClipHandler(clips *repository.ClipStore, service *services.ClipService) *ClipHandler {
	return &ClipHandler{clips: clips, service: service}
}

func (h *ClipHandler) Create(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	var req struct {
		Start float64 `json:"start"`
		End   float64 `json:"end"`
		Title string  `json:"title"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	task, err := h.service.Start(c.UserContext(), mediaID, req.Start, req.End, req.Title)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Media not found")
		}
		return response.Error(c, fiber.StatusBadRequest, err.Error())
	}
	return c.Status(fiber.StatusAccepted).JSON(task)
}

func (h *ClipHandler) Get(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid clip ID")
	}
	task, err := h.clips.Get(c.UserContext(), id)
	if err != nil {
		return repoError(c, err, "Clip not found", "Failed to load clip")
	}
	return c.JSON(task)
}

func (h *ClipHandler) List(c *fiber.Ctx) error {
	tasks, err := h.clips.List(c.UserContext())
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to load clips")
	}
	if tasks == nil {
		tasks = []models.ClipTask{}
	}
	return c.JSON(tasks)
}

func (h *ClipHandler) Cancel(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid clip ID")
	}
	if !h.service.Cancel(id) {
		return response.Error(c, fiber.StatusNotFound, "Clip is not running")
	}
	return c.SendStatus(fiber.StatusNoContent)
}
