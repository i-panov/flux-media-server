package handlers

import (
	"errors"
	"log"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// AdminHandler обслуживает админку хранилища: диск, карантин оригиналов,
// ручной ретрай заданий. Все роуты — за requireAdmin.
type AdminHandler struct {
	mediaRepo  repository.MediaRepository
	taskRepo   repository.TranscodeTaskRepository
	transQueue TranscodeQueue
	storageCfg config.StorageConfig
	mediaCfg   config.MediaConfig
}

func NewAdminHandler(
	mediaRepo repository.MediaRepository,
	taskRepo repository.TranscodeTaskRepository,
	transQueue TranscodeQueue,
	storageCfg config.StorageConfig,
	mediaCfg config.MediaConfig,
) *AdminHandler {
	return &AdminHandler{
		mediaRepo:  mediaRepo,
		taskRepo:   taskRepo,
		transQueue: transQueue,
		storageCfg: storageCfg,
		mediaCfg:   mediaCfg,
	}
}

type diskInfo struct {
	Path       string `json:"path"`
	TotalBytes int64  `json:"total_bytes"`
	FreeBytes  int64  `json:"free_bytes"`
}

type storageInfoResponse struct {
	Disks          []diskInfo `json:"disks"`
	VideoBytes     int64      `json:"video_bytes"`
	AudioBytes     int64      `json:"audio_bytes"`
	OriginalsBytes int64      `json:"originals_bytes"`
	TempBytes      int64      `json:"temp_bytes"`
	AutoCleanup    bool       `json:"auto_cleanup"`
}

// StorageInfo возвращает занятость дисков и каталогов. Дорогой обход
// (filepath.Walk) — только по явному запросу админа, не фоном.
func (h *AdminHandler) StorageInfo(c *fiber.Ctx) error {
	seen := make(map[string]bool)
	var disks []diskInfo
	for _, dir := range []string{h.mediaCfg.VideoPath, h.mediaCfg.AudioPath, h.storageCfg.OriginalsDir, h.storageCfg.TempDir} {
		if dir == "" || seen[dir] {
			continue
		}
		seen[dir] = true
		total, free := services.DiskUsage(dir)
		disks = append(disks, diskInfo{Path: dir, TotalBytes: total, FreeBytes: free})
	}
	return c.JSON(storageInfoResponse{
		Disks:          disks,
		VideoBytes:     dirSizeBytes(h.mediaCfg.VideoPath),
		AudioBytes:     dirSizeBytes(h.mediaCfg.AudioPath),
		OriginalsBytes: dirSizeBytes(h.storageCfg.OriginalsDir),
		TempBytes:      dirSizeBytes(h.storageCfg.TempDir),
		AutoCleanup:    h.storageCfg.AutoCleanupOriginals,
	})
}

// dirSizeBytes суммирует размеры файлов дерева. Ошибки отдельных
// ветвей пропускаются (best-effort для админки).
func dirSizeBytes(root string) int64 {
	var total int64
	_ = filepath.Walk(root, func(_ string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total
}

type originalItem struct {
	Name     string `json:"name"`
	Size     int64  `json:"size_bytes"`
	Modified string `json:"modified"`
	Status   string `json:"status"`
	MediaID  uint   `json:"media_id,omitempty"`
	Views    uint64 `json:"views"`
}

// OriginalsList возвращает карантин со статусами заданий и просмотрами
// в порядке чистки (меньше просмотров → больше размер).
func (h *AdminHandler) OriginalsList(c *fiber.Ctx) error {
	infos, err := h.transQueue.OriginalsStatus()
	if err != nil {
		log.Printf("admin: list originals: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to list originals")
	}
	items := make([]originalItem, 0, len(infos))
	for _, info := range infos {
		items = append(items, originalItem{
			Name:     info.Name,
			Size:     info.Size,
			Modified: info.Modified.UTC().Format("2006-01-02T15:04:05Z"),
			Status:   info.Status,
			MediaID:  info.MediaID,
			Views:    info.Views,
		})
	}
	return c.JSON(items)
}

// cleanOriginalName проверяет имя из URL: только плоское имя файла,
// без разделителей и .. (иначе — путь к обходу карантина).
func cleanOriginalName(name string) (string, bool) {
	if name == "" || name == "." || name == ".." {
		return "", false
	}
	if name != path.Base(name) {
		return "", false
	}
	return name, true
}

func (h *AdminHandler) originalPath(name string) (string, bool) {
	clean, ok := cleanOriginalName(name)
	if !ok {
		return "", false
	}
	full := filepath.Join(h.storageCfg.OriginalsDir, clean)
	if !services.IsSubPath(h.storageCfg.OriginalsDir, full) {
		return "", false
	}
	return full, true
}

// OriginalDownload отдаёт оригинал как есть (для проверки/перекачки).
func (h *AdminHandler) OriginalDownload(c *fiber.Ctx) error {
	full, ok := h.originalPath(c.Params("name"))
	if !ok {
		return response.Error(c, fiber.StatusBadRequest, "Invalid file name")
	}
	st, err := os.Stat(full)
	if err != nil || st.IsDir() {
		return response.Error(c, fiber.StatusNotFound, "Original not found")
	}
	// Кавычка в имени ломала бы заголовок (инъекция параметра) — меняем
	// её только для заголовка, файл на диске не трогаем.
	safeName := strings.ReplaceAll(st.Name(), `"`, "_")
	c.Set("Content-Disposition", "attachment; filename=\""+safeName+"\"")
	return c.SendFile(full)
}

// OriginalDelete удаляет оригинал из карантина. Активное задание
// отменяется (воркер дочищает), история заданий остаётся.
// Идемпотентно: файла уже нет — тоже успех (DELETE semantics),
// иначе админка видела бы ошибку и повторяла запрос.
func (h *AdminHandler) OriginalDelete(c *fiber.Ctx) error {
	full, ok := h.originalPath(c.Params("name"))
	if !ok {
		return response.Error(c, fiber.StatusBadRequest, "Invalid file name")
	}
	if err := h.transQueue.CancelBySource(full); err != nil {
		log.Printf("admin: cancel task for %s: %v", full, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel task")
	}
	if err := os.Remove(full); err != nil {
		if os.IsNotExist(err) {
			return c.SendStatus(fiber.StatusNoContent)
		}
		log.Printf("admin: remove original %s: %v", full, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete original")
	}
	return c.SendStatus(fiber.StatusNoContent)
}

// TranscodeRetry возвращает failed-задание в очередь.
func (h *AdminHandler) TranscodeRetry(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil || id <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid job ID")
	}

	switch err := h.transQueue.Retry(uint64(id)); {
	case errors.Is(err, services.ErrTranscodeJobNotFound):
		return response.Error(c, fiber.StatusNotFound, "Transcode job not found")
	case errors.Is(err, services.ErrTranscodeJobDone):
		return response.Error(c, fiber.StatusConflict, "Transcode job already completed")
	case errors.Is(err, services.ErrTranscodeJobNotFailed):
		return response.Error(c, fiber.StatusConflict, "Only failed jobs can be retried")
	case errors.Is(err, services.ErrTranscodeConflict):
		return response.Error(c, fiber.StatusConflict, "Transcode job state changed, retry")
	case err != nil:
		log.Printf("admin: retry transcode %d: %v", id, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to retry transcode job")
	}
	return c.SendStatus(fiber.StatusAccepted)
}
