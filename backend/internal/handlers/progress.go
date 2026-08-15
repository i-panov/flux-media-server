package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type ProgressHandler struct {
	progressRepo repository.ProgressRepository
	mediaRepo    repository.MediaRepository
}

func NewProgressHandler(progressRepo repository.ProgressRepository, mediaRepo repository.MediaRepository) *ProgressHandler {
	return &ProgressHandler{
		progressRepo: progressRepo,
		mediaRepo:    mediaRepo,
	}
}

type UpdateProgressRequest struct {
	Position  int  `json:"position"`
	Duration  int  `json:"duration"`  // общая длительность в секундах
	Completed bool `json:"completed"` // просмотрено до конца
}

func (h *ProgressHandler) List(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	limit, offset := response.ClampPage(c.QueryInt("limit", defaultPageSize), c.QueryInt("offset", 0), defaultPageSize)

	ctx := c.UserContext()
	progress, total, err := h.progressRepo.FindByUser(ctx, userID, limit, offset)
	if err != nil {
		log.Printf("FindByUser: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch progress")
	}
	if progress == nil {
		progress = []models.WatchProgress{}
	}

	return response.Paginated(c, progress, total, limit, offset)
}

func (h *ProgressHandler) Update(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	var req UpdateProgressRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Position < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Position must be non-negative")
	}
	if req.Duration < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Duration must be non-negative")
	}
	// Позиция за пределами длительности — признак испорченного клиента;
	// при неизвестной длительности (0) проверка пропускается.
	if req.Duration > 0 && req.Position > req.Duration {
		return response.Error(c, fiber.StatusBadRequest, "Position must not exceed duration")
	}

	ctx := c.UserContext()

	// Проверяем существование медиа до создания/обновления прогресса.
	if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	progress, err := h.progressRepo.FindByUserAndMedia(ctx, userID, mediaID)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("FindByUserAndMedia: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Internal server error")
		}
		progress = &models.WatchProgress{
			UserID:  userID,
			MediaID: mediaID,
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
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Delete не возвращает RowsAffected через интерфейс, поэтому
	// отсутствие записи определяем предварительным поиском.
	if _, err := h.progressRepo.FindByUserAndMedia(ctx, userID, mediaID); err != nil {
		return repoError(c, err, "Progress not found", "Failed to delete progress")
	}

	if err := h.progressRepo.Delete(ctx, userID, mediaID); err != nil {
		log.Printf("Delete progress: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete progress")
	}

	return c.JSON(fiber.Map{"message": "Progress deleted successfully"})
}
