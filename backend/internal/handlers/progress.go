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

	// Прогресс существует только для видео. Аудио всегда стартует
	// с начала, поэтому остальные типы здесь не отдаём.
	mediaType := models.MediaTypeVideo
	if rawType := c.Query("type"); rawType != "" {
		parsed := models.ParseMediaType(rawType)
		if !parsed.Valid() {
			return response.Error(c, fiber.StatusBadRequest, "invalid type")
		}
		if parsed != models.MediaTypeVideo {
			return response.Paginated(c, []models.WatchProgress{}, 0, limit, offset)
		}
	}

	ctx := c.UserContext()
	progress, total, err := h.progressRepo.FindByUser(ctx, userID, mediaType, limit, offset)
	if err != nil {
		log.Printf("FindByUser: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch progress")
	}
	if progress == nil {
		progress = []models.WatchProgress{}
	}

	return response.Paginated(c, progress, total, limit, offset)
}

// / GetOne возвращает прогресс текущего пользователя для одного медиа.
// / Нужен resume-диалогу видеоплеера: тянуть весь список ради одного
// / mediaId — лишний трафик и задержка перед стартом.
func (h *ProgressHandler) GetOne(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	media, err := h.mediaRepo.FindByID(c.UserContext(), mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}
	if media.Type != models.MediaTypeVideo {
		// Контракт shared-клиентов: валидный объект прогресса, но нулевой.
		// GET аудио всегда начинает с начала.
		return c.JSON(models.WatchProgress{
			UserID: userID, MediaID: mediaID, Position: 0, Duration: 0,
		})
	}
	progress, err := h.progressRepo.FindByUserAndMedia(c.UserContext(), userID, mediaID)
	if err != nil {
		return repoError(c, err, "Progress not found", "Failed to fetch progress")
	}

	return c.JSON(progress)
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
	media, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}
	if media.Type != models.MediaTypeVideo {
		// Заодно убираем старые записи, созданные до этого правила.
		_ = h.progressRepo.Delete(ctx, userID, mediaID)
		return c.JSON(models.WatchProgress{
			UserID: userID, MediaID: mediaID, Position: 0, Duration: 0,
		})
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
