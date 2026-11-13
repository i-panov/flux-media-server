package handlers

import (
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"

	"gorm.io/gorm"

	"flux/internal/config"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// UploadHandler handles file uploads.
type UploadHandler struct {
	mediaRepo  repository.MediaRepository
	queue      *services.UploadQueue
	transQueue TranscodeQueue
	mediaCfg   config.MediaConfig
	storageCfg config.StorageConfig
	config     UploadConfig
}

// UploadConfig holds upload-specific configuration.
type UploadConfig struct {
	MaxFileSize int64
}

// NewUploadHandler creates a new UploadHandler. Файл валидируется и
// сохраняется синхронно, обработка (хэш/ffprobe/превью) — в фоне через
// queue; thumbSvc передаётся внутрь очереди, хендлеру он не нужен.
// Видео уходят в карантин и нормализуются transQueue, аудио и картинки —
// старым путём через queue.
func NewUploadHandler(
	mediaRepo repository.MediaRepository,
	queue *services.UploadQueue,
	transQueue TranscodeQueue,
	mediaCfg config.MediaConfig,
	storageCfg config.StorageConfig,
	config UploadConfig,
) *UploadHandler {
	return &UploadHandler{
		mediaRepo:  mediaRepo,
		queue:      queue,
		transQueue: transQueue,
		mediaCfg:   mediaCfg,
		storageCfg: storageCfg,
		config:     config,
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

	// force пропускает проверку похожих картинок (pHash), но не точного
	// дубля по хэшу: подтверждение пользователя относится только к
	// «похоже, уже есть».
	force, _ := strconv.ParseBool(c.FormValue("force"))

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
	if mediaType == models.MediaTypeVideo {
		return h.uploadVideo(c, fileHeader, filename)
	}
	destPath := h.mediaCfg.VideoPath
	switch mediaType {
	case models.MediaTypeAudio:
		destPath = h.mediaCfg.AudioPath
	case models.MediaTypeImage:
		destPath = h.mediaCfg.ImagePath
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
		// Файл есть: чей он? Живая строка — честный 409. Trashed-строка —
		// 409 с намёком на корзину (файл принадлежит ей, восстанавливать
		// оттуда). Ничья строка — сирота отменённой/упавшей загрузки:
		// сносим stale-файл и принимаем загрузку, иначе повтор вечно
		// упирался бы в 409, а файла не было бы видно в приложении.
		existing, err := h.mediaRepo.FindByPathBasic(c.UserContext(), dstPath)
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("upload: FindByPath %s: %v", dstPath, err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to check file")
		}
		if err == nil && existing != nil && existing.ID != 0 {
			if existing.DeletedAt.Valid {
				return response.Error(c, fiber.StatusConflict, "File exists in trash — restore it from trash")
			}
			return response.Error(c, fiber.StatusConflict, "File already exists")
		}
		// Ничья строка: файл может принадлежать активному заданию.
		// Не удаляем и не перезаписываем — ниже O_EXCL сохранит под
		// следующим свободным именем.
	}

	// O_EXCL + уникальное имя: параллельные загрузки не перезаписывают
	// друг друга и не удаляют файл активного задания.
	savedPath, saveErr := saveUploadExclusive(c, fileHeader, destPath, filename)
	if saveErr != nil {
		log.Printf("upload: save file: %v", saveErr)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save file")
	}
	dstPath = savedPath
	filename = filepath.Base(dstPath)

	jobID, err := h.queue.Enqueue(services.UploadJobInput{
		FilePath:  dstPath,
		Filename:  filename,
		MediaType: mediaType,
		Force:     force,
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

	return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"job_id": jobID, "job_type": "upload"})
}

// uploadVideo принимает видео в карантин для нормализации. В отличие от
// аудио-пути, 409 за то же имя здесь нет: коллизии разруливаются
// уникальным именем, а настоящие дубли — асинхронным хэш-дедупом
// в воркере (файл уже на диске, синхронно хэшировать гигабайты нельзя).
func (h *UploadHandler) uploadVideo(c *fiber.Ctx, fileHeader *multipart.FileHeader, filename string) error {
	if h.storageCfg.OriginalsDir == "" {
		return response.Error(c, fiber.StatusInternalServerError, "Originals directory is not configured")
	}
	if err := os.MkdirAll(h.storageCfg.OriginalsDir, 0755); err != nil {
		log.Printf("upload: mkdir %s: %v", h.storageCfg.OriginalsDir, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create directory")
	}

	// Место в карантине — до сохранения (с авточисткой, если включена).
	if err := h.transQueue.EnsureSpaceForUpload(fileHeader.Size); err != nil {
		if errors.Is(err, services.ErrInsufficientSpace) {
			return response.Error(c, fiber.StatusInsufficientStorage, "Not enough disk space for upload")
		}
		log.Printf("upload: space check: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to check disk space")
	}

	dstPath, err := saveUploadExclusive(c, fileHeader, h.storageCfg.OriginalsDir, filename)
	if err != nil {
		if errors.Is(err, services.ErrDestinationExists) {
			return response.Error(c, fiber.StatusConflict, "Too many files with this name, rename and retry")
		}
		log.Printf("upload: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save file")
	}

	taskID, err := h.transQueue.Enqueue(dstPath, filename)
	if err != nil {
		log.Printf("upload: enqueue transcode: %v", err)
		if rmErr := os.Remove(dstPath); rmErr != nil {
			log.Printf("upload: remove orphaned file %s: %v", dstPath, rmErr)
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to queue file")
	}

	// Ключ ответа — тот же job_id плюс тип задания: клиент с job_type
	// опрашивает нужный эндпоинт (/uploads/:id или /transcodes/:id),
	// а fallback в UploadStatus остаётся для старых клиентов.
	return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"job_id": taskID, "job_type": "transcode"})
}

// saveUploadExclusive сохраняет загрузку под свободным именем:
// исходное, затем `base (2).ext`… Создание — O_EXCL, поэтому две
// параллельные загрузки не перезаписывают друг друга: вторая
// получает следующее имя. Исчерпание (1000 попыток) — ошибка,
// а не молчаливая перезапись существующего файла.
func saveUploadExclusive(c *fiber.Ctx, fileHeader *multipart.FileHeader, dir, filename string) (string, error) {
	ext := filepath.Ext(filename)
	base := strings.TrimSuffix(filename, ext)
	for i := 0; i < 1000; i++ {
		candidate := filename
		if i > 0 {
			candidate = fmt.Sprintf("%s (%d)%s", base, i+1, ext)
		}
		full := filepath.Join(dir, candidate)
		if !services.IsSubPath(dir, full) {
			return "", fmt.Errorf("invalid filename: %s", filename)
		}
		out, err := os.OpenFile(full, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
		if err != nil {
			if os.IsExist(err) {
				continue
			}
			return "", err
		}
		src, err := fileHeader.Open()
		if err != nil {
			out.Close()
			os.Remove(full)
			return "", err
		}
		_, copyErr := io.Copy(out, src)
		src.Close()
		closeErr := out.Close()
		if copyErr != nil || closeErr != nil {
			os.Remove(full)
			if copyErr != nil {
				return "", copyErr
			}
			return "", closeErr
		}
		return full, nil
	}
	return "", fmt.Errorf("%w: %s", services.ErrDestinationExists, filename)
}

// UploadStatus returns the current status of an upload job.
// Задания нормализации (job_id из видео-загрузок) тоже резолвятся здесь:
// пространства ID могут пересекаться, поэтому сначала очередь загрузок
// (старое поведение — без изменений), затем транскод.
func (h *UploadHandler) UploadStatus(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	status, ok := h.queue.Status(uint64(id))
	if !ok {
		if st, ok := h.transQueue.Get(uint64(id)); ok {
			return c.JSON(transcodeStatusResponse(c, h.mediaRepo, id, st))
		}
		return response.Error(c, fiber.StatusNotFound, "Upload job not found")
	}

	resp := fiber.Map{
		"id":       id,
		"job_type": "upload",
		"status":   status.Status,
		"error":    nil,
		"media":    nil,
	}
	if status.Error != "" {
		resp["error"] = status.Error
	}
	if status.Status == services.UploadJobDuplicate && status.DuplicateMediaID != 0 {
		resp["duplicate"] = fiber.Map{
			"id":    status.DuplicateMediaID,
			"title": status.DuplicateTitle,
		}
	}
	if status.Status == services.UploadJobDone && status.MediaID != 0 {
		media, err := h.mediaRepo.FindByID(c.UserContext(), status.MediaID)
		if err != nil {
			// Запись удалена отдельно (например, через DELETE /media/:id) —
			// отдаём media:null, это не сбой API.
			log.Printf("UploadStatus: FindByID %d: %v", status.MediaID, err)
		} else {
			resp["media"] = media
		}
	}
	return c.JSON(resp)
}

// CancelUpload cancels a pending or in-flight upload job (204) and removes
// the file and media record. Finished jobs cannot be cancelled (409).
// Задания транскода отменяются тем же путём (fallback, как в статусе).
func (h *UploadHandler) CancelUpload(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	switch err := h.queue.Cancel(uint64(id)); {
	case errors.Is(err, services.ErrUploadJobNotFound):
		switch err := h.transQueue.Cancel(uint64(id)); {
		case errors.Is(err, services.ErrTranscodeJobNotFound):
			return response.Error(c, fiber.StatusNotFound, "Upload job not found")
		case errors.Is(err, services.ErrTranscodeJobDone):
			return response.Error(c, fiber.StatusConflict, "Upload job already completed")
		case errors.Is(err, services.ErrTranscodeConflict):
			return response.Error(c, fiber.StatusConflict, "Upload job state changed, retry")
		case err != nil:
			log.Printf("CancelUpload: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel upload job")
		}
		return c.SendStatus(fiber.StatusNoContent)
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
