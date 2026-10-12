package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/middleware"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// ExtractQueue — узкий интерфейс очереди извлечения: хендлеру нужны
// постановка, статус, отмена и доступность ffmpeg (тесты подменяют
// стабом без ffmpeg).
type ExtractQueue interface {
	Enqueue(sourceID uint) (uint64, error)
	Get(id uint64) (status, errMsg string, mediaID uint, ok bool)
	Cancel(id uint64) error
	Available() bool
}

// ExtractHandler обслуживает извлечение аудиодорожки из видео.
type ExtractHandler struct {
	mediaRepo repository.MediaRepository
	queue     ExtractQueue
}

func NewExtractHandler(mediaRepo repository.MediaRepository, queue ExtractQueue) *ExtractHandler {
	return &ExtractHandler{mediaRepo: mediaRepo, queue: queue}
}

// Extract ставит извлечение аудио в очередь: 202 {job_id}.
// Если трек уже извлечён (связка source_media_id) — сразу 200 {media},
// без нового задания и ffmpeg.
func (h *ExtractHandler) Extract(c *fiber.Ctx) error {
	if _, ok := middleware.GetUserID(c); !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	if !h.queue.Available() {
		return response.Error(c, fiber.StatusServiceUnavailable, "Audio extraction unavailable: ffmpeg not installed")
	}

	ctx := c.UserContext()
	source, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}
	if !source.Type.IsVideo() {
		return response.Error(c, fiber.StatusBadRequest, "Source must be a video")
	}

	if existing, err := h.mediaRepo.FindBySourceMediaID(ctx, mediaID); err == nil {
		return c.JSON(existing)
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		log.Printf("Extract: FindBySourceMediaID %d: %v", mediaID, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to check existing track")
	}

	jobID, err := h.queue.Enqueue(mediaID)
	if err != nil {
		log.Printf("extract: enqueue %d: %v", mediaID, err)
		if errors.Is(err, services.ErrExtractQueueFull) {
			return response.Error(c, fiber.StatusTooManyRequests, "Extract queue is full")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to queue extraction")
	}

	return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"job_id": jobID})
}

// ExtractStatus возвращает статус задания: {id, status, error, media}.
// Формат — как у upload-статуса, фронт переиспользует модель.
func (h *ExtractHandler) ExtractStatus(c *fiber.Ctx) error {
	if _, ok := middleware.GetUserID(c); !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	id, err := c.ParamsInt("id")
	if err != nil || id <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	status, errMsg, mediaID, ok := h.queue.Get(uint64(id))
	if !ok {
		return response.Error(c, fiber.StatusNotFound, "Extract job not found")
	}

	resp := fiber.Map{
		"id":     id,
		"status": status,
		"error":  nil,
		"media":  nil,
	}
	if errMsg != "" {
		resp["error"] = errMsg
	}
	if status == services.ExtractJobDone && mediaID != 0 {
		media, err := h.mediaRepo.FindByID(c.UserContext(), mediaID)
		if err != nil {
			// Запись удалена отдельно — отдаём media:null, не сбой API.
			log.Printf("ExtractStatus: FindByID %d: %v", mediaID, err)
		} else {
			resp["media"] = media
		}
	}
	return c.JSON(resp)
}

// Extracted возвращает аудиотрек, извлечённый из видео mediaID,
// или 404. Экран видео по нему решает: кнопка «перейти к треку»
// вместо «извлечь». Soft-deleted трек связку разрывает (gorm-скоуп),
// и экран снова показывает извлечение.
func (h *ExtractHandler) Extracted(c *fiber.Ctx) error {
	if _, ok := middleware.GetUserID(c); !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	media, err := h.mediaRepo.FindBySourceMediaID(c.UserContext(), mediaID)
	if err != nil {
		return repoError(c, err, "No extracted track", "Failed to fetch extracted track")
	}
	return c.JSON(media)
}

// CancelExtract отменяет задание извлечения (204). Готовое — 409.
func (h *ExtractHandler) CancelExtract(c *fiber.Ctx) error {
	if _, ok := middleware.GetUserID(c); !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	id, err := c.ParamsInt("id")
	if err != nil || id <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	switch err := h.queue.Cancel(uint64(id)); {
	case errors.Is(err, services.ErrExtractJobNotFound):
		return response.Error(c, fiber.StatusNotFound, "Extract job not found")
	case errors.Is(err, services.ErrExtractJobDone):
		return response.Error(c, fiber.StatusConflict, "Extract job already completed")
	case err != nil:
		log.Printf("CancelExtract: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel extract job")
	}
	return c.SendStatus(fiber.StatusNoContent)
}
