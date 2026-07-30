package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type ProgressHandler struct {
	progressRepo repository.ProgressRepository
}

func NewProgressHandler(progressRepo repository.ProgressRepository) *ProgressHandler {
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
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	limit := c.QueryInt("limit", 50)
	offset := c.QueryInt("offset", 0)
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	ctx := c.UserContext()
	progress, total, err := h.progressRepo.FindByUser(ctx, userID, limit, offset)
	if err != nil {
		log.Printf("FindByUser: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch progress")
	}

	return c.JSON(fiber.Map{
		"items":  progress,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

func (h *ProgressHandler) Update(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	var req UpdateProgressRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Position < 0 || req.Duration < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Position and duration must be non-negative")
	}
	if req.Duration > 0 && req.Position > req.Duration {
		return response.Error(c, fiber.StatusBadRequest, "Position must not exceed duration")
	}

	ctx := c.UserContext()
	progress, err := h.progressRepo.FindByUserAndMedia(ctx, userID, uint(mediaID))
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("FindByUserAndMedia: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Internal server error")
		}
		progress = &models.WatchProgress{
			UserID:  userID,
			MediaID: uint(mediaID),
		}
	}

	progress.Position = req.Position
	progress.Duration = req.Duration
	progress.Completed = req.Completed

	if err := h.progressRepo.Upsert(ctx, progress); err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update progress")
	}

	return c.JSON(progress)
}

func (h *ProgressHandler) Delete(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	if err := h.progressRepo.Delete(ctx, userID, uint(mediaID)); err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete progress")
	}

	return c.JSON(fiber.Map{"message": "Progress deleted successfully"})
}
