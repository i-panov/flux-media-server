package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// TranscodeQueue — узкий интерфейс очереди нормализации для хендлеров.
// Паттерн — как ExtractQueue: хендлеры тестируются со стабом, сервис
// отдельно с фейковым раннером.
type TranscodeQueue interface {
	Enqueue(sourcePath, filename string) (uint64, error)
	Get(id uint64) (services.TranscodeJobStatus, bool)
	Cancel(id uint64) error
	CancelBySource(sourcePath string) error
	Retry(id uint64) error
	EnsureSpaceForUpload(fileSize int64) error
	OriginalsStatus() ([]services.OriginalInfo, error)
}

// TranscodeHandler обслуживает статусы заданий нормализации.
type TranscodeHandler struct {
	mediaRepo repository.MediaRepository
	queue     TranscodeQueue
}

func NewTranscodeHandler(mediaRepo repository.MediaRepository, queue TranscodeQueue) *TranscodeHandler {
	return &TranscodeHandler{mediaRepo: mediaRepo, queue: queue}
}

// TranscodeStatus возвращает статус задания. Форма — как у загрузок
// плюс прогресс/скорость/ETA.
func (h *TranscodeHandler) TranscodeStatus(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	st, ok := h.queue.Get(uint64(id))
	if !ok {
		return response.Error(c, fiber.StatusNotFound, "Transcode job not found")
	}

	return c.JSON(transcodeStatusResponse(c, h.mediaRepo, id, st))
}

// TranscodeCancel отменяет задание нормализации.
func (h *TranscodeHandler) TranscodeCancel(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	switch err := h.queue.Cancel(uint64(id)); {
	case errors.Is(err, services.ErrTranscodeJobNotFound):
		return response.Error(c, fiber.StatusNotFound, "Transcode job not found")
	case errors.Is(err, services.ErrTranscodeJobDone):
		return response.Error(c, fiber.StatusConflict, "Transcode job already completed")
	case errors.Is(err, services.ErrTranscodeConflict):
		return response.Error(c, fiber.StatusConflict, "Transcode job state changed, retry")
	case err != nil:
		log.Printf("TranscodeCancel: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel transcode job")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

// transcodeStatusResponse собирает ответ статуса: та же форма, что у
// загрузок ({id,status,error,media}), плюс прогресс. Используется и
// здесь, и в fallback'е UploadStatus.
func transcodeStatusResponse(c *fiber.Ctx, mediaRepo repository.MediaRepository, id int, st services.TranscodeJobStatus) fiber.Map {
	resp := fiber.Map{
		"id":          id,
		"status":      st.Status,
		"error":       nil,
		"media":       nil,
		"progress":    st.Progress,
		"speed":       st.Speed,
		"eta_seconds": st.ETASeconds,
	}
	if st.Error != "" {
		resp["error"] = st.Error
	}
	if st.Status == services.TranscodeTaskDone && st.MediaID != 0 {
		media, err := mediaRepo.FindByID(c.UserContext(), st.MediaID)
		if err != nil {
			log.Printf("TranscodeStatus: FindByID %d: %v", st.MediaID, err)
		} else {
			resp["media"] = media
		}
	}
	return resp
}
