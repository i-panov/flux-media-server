package handlers

import (
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// UploadHandler handles file uploads.
type UploadHandler struct {
	mediaRepo repository.MediaRepository
	queue     *services.UploadQueue
	config    UploadConfig
	mediaCfg  config.MediaConfig
}

// UploadConfig holds upload-specific configuration.
type UploadConfig struct {
	MaxFileSize int64
}

// NewUploadHandler creates a new UploadHandler. Файл валидируется и
// сохраняется синхронно, обработка (хэш/ffprobe/превью) — в фоне через
// queue; thumbSvc передаётся внутрь очереди, хендлеру он не нужен.
func NewUploadHandler(
	mediaRepo repository.MediaRepository,
	queue *services.UploadQueue,
	mediaCfg config.MediaConfig,
	config UploadConfig,
) *UploadHandler {
	return &UploadHandler{
		mediaRepo: mediaRepo,
		queue:     queue,
		mediaCfg:  mediaCfg,
		config:    config,
	}
}

// Upload handles multipart file upload. Файл валидируется и сохраняется
// синхронно; хэш, ffprobe и превью выполняются воркером очереди в фоне.
// Ответ — 202 с job_id; статус обработки — GET /api/media/uploads/:id.
func (h *UploadHandler) Upload(c *fiber.Ctx) error {
	// Тип определяем консистентно: заданный валидный media_type имеет
	// приоритет (он и каталог выбирает, и в запись Type попадает);
	// при отсутствии media_type — по расширению файла.
	rawType := c.FormValue("media_type")
	mediaType := models.MediaTypeVideo
	if rawType != "" {
		mediaType = models.ParseMediaType(rawType)
		if !mediaType.Valid() {
			return response.Error(c, fiber.StatusBadRequest, "Invalid media_type")
		}
	}

	// Get uploaded file.
	fileHeader, err := c.FormFile("file")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "File is required")
	}

	// Check file is not empty.
	if fileHeader.Size == 0 {
		return response.Error(c, fiber.StatusBadRequest, "File is empty")
	}

	// Check file size.
	if h.config.MaxFileSize > 0 && fileHeader.Size > h.config.MaxFileSize {
		return response.Error(c, fiber.StatusRequestEntityTooLarge, "File too large")
	}

	// Sanitize the filename to prevent path traversal attacks.
	filename, err := services.SanitizeFilename(fileHeader.Filename)
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid filename")
	}

	// Check extension.
	ext := strings.ToLower(filepath.Ext(filename))
	if !h.isAllowedExtension(ext) {
		return response.Error(c, fiber.StatusBadRequest, "File type not allowed: "+ext)
	}

	// Resolve destination path by media_type.
	if rawType == "" {
		mediaType = services.DetermineMediaType(filename)
	}
	destPath := h.mediaCfg.VideoPath
	if mediaType == models.MediaTypeAudio {
		destPath = h.mediaCfg.AudioPath
	}
	if destPath == "" {
		return response.Error(c, fiber.StatusInternalServerError, "No path configured for media type: "+string(mediaType))
	}

	// Ensure destination directory exists.
	if err := os.MkdirAll(destPath, 0755); err != nil {
		log.Printf("upload: mkdir %s: %v", destPath, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create directory")
	}

	// Save file to destination path.
	dstPath := filepath.Join(destPath, filename)
	if !services.IsSubPath(destPath, dstPath) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid filename")
	}

	// Check if file already exists.
	if _, err := os.Stat(dstPath); err == nil {
		return response.Error(c, fiber.StatusConflict, "File already exists")
	}

	if err := c.SaveFile(fileHeader, dstPath); err != nil {
		log.Printf("upload: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save file")
	}

	jobID, err := h.queue.Enqueue(services.UploadJobInput{
		FilePath:  dstPath,
		Filename:  filename,
		MediaType: mediaType,
	})
	if err != nil {
		log.Printf("upload: enqueue: %v", err)
		// Убираем осиротевший файл: задание в очередь не попало.
		if rmErr := os.Remove(dstPath); rmErr != nil {
			log.Printf("upload: remove orphaned file %s: %v", dstPath, rmErr)
		}
		if errors.Is(err, services.ErrUploadQueueFull) {
			return response.Error(c, fiber.StatusTooManyRequests, "Upload queue is full")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to queue file")
	}

	return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"job_id": jobID})
}

// UploadStatus returns the current status of an upload job.
func (h *UploadHandler) UploadStatus(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	status, errMsg, mediaID, ok := h.queue.Get(uint64(id))
	if !ok {
		return response.Error(c, fiber.StatusNotFound, "Upload job not found")
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
	if status == services.UploadJobDone && mediaID != 0 {
		media, err := h.mediaRepo.FindByID(c.UserContext(), mediaID)
		if err != nil {
			// Запись удалена отдельно (например, через DELETE /media/:id) —
			// отдаём media:null, это не сбой API.
			log.Printf("UploadStatus: FindByID %d: %v", mediaID, err)
		} else {
			resp["media"] = media
		}
	}
	return c.JSON(resp)
}

// CancelUpload cancels a pending or in-flight upload job (204) and removes
// the file and media record. Finished jobs cannot be cancelled (409).
func (h *UploadHandler) CancelUpload(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id < 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	switch err := h.queue.Cancel(uint64(id)); {
	case errors.Is(err, services.ErrUploadJobNotFound):
		return response.Error(c, fiber.StatusNotFound, "Upload job not found")
	case errors.Is(err, services.ErrUploadJobDone):
		return response.Error(c, fiber.StatusConflict, "Upload job already completed")
	case err != nil:
		log.Printf("CancelUpload: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel upload job")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *UploadHandler) isAllowedExtension(ext string) bool {
	return services.IsAllowedExtension(ext)
}
