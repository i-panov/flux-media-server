package handlers

import (
	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
)

type ProgressHandler struct {
	progressRepo *repository.ProgressRepository
}

func NewProgressHandler(progressRepo *repository.ProgressRepository) *ProgressHandler {
	return &ProgressHandler{
		progressRepo: progressRepo,
	}
}

type UpdateProgressRequest struct {
	Position  int  `json:"position"`
	Duration  int  `json:"duration"`
	Completed bool `json:"completed"`
}

func (h *ProgressHandler) List(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Unauthorized",
		})
	}

	progress, err := h.progressRepo.FindByUser(userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to fetch progress",
		})
	}

	return c.JSON(progress)
}

func (h *ProgressHandler) Update(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Unauthorized",
		})
	}
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	var req UpdateProgressRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	progress, err := h.progressRepo.FindByUserAndMedia(userID, uint(mediaID))
	if err != nil {
		progress = &models.WatchProgress{
			UserID:  userID,
			MediaID: uint(mediaID),
		}
	}

	progress.Position = req.Position
	progress.Duration = req.Duration
	progress.Completed = req.Completed

	if err := h.progressRepo.Upsert(progress); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to update progress",
		})
	}

	return c.JSON(progress)
}

func (h *ProgressHandler) Delete(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Unauthorized",
		})
	}
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid media ID",
		})
	}

	if err := h.progressRepo.Delete(userID, uint(mediaID)); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to delete progress",
		})
	}

	return c.JSON(fiber.Map{
		"message": "Progress deleted successfully",
	})
}
