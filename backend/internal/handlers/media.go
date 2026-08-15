package handlers

import (
	"errors"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// defaultMediaPageSize — размер страницы по умолчанию в списке медиа.
const defaultMediaPageSize = 20

type MediaHandler struct {
	mediaRepo repository.MediaRepository
	streamer  services.StreamerInterface
	thumbSvc  *services.ThumbnailService
}

func NewMediaHandler(mediaRepo repository.MediaRepository, streamer services.StreamerInterface, thumbSvc *services.ThumbnailService) *MediaHandler {
	return &MediaHandler{
		mediaRepo: mediaRepo,
		streamer:  streamer,
		thumbSvc:  thumbSvc,
	}
}

type CreateMediaRequest struct {
	Title       string           `json:"title"`
	Year        int              `json:"year"`
	Description string           `json:"description"`
	Type        models.MediaType `json:"type"`
	FilePath    string           `json:"file_path"`
}

// isValidMediaType возвращает true для пустой строки или валидного типа.
// (Используется в Create/Update: там пустой тип валиден только при проверке
// на обязательность отдельным условием.)
func isValidMediaType(t string) bool {
	return t == "" || models.ParseMediaType(t).Valid()
}

func (h *MediaHandler) List(c *fiber.Ctx) error {
	var filters repository.MediaFilters

	if mediaType := c.Query("type"); mediaType != "" {
		mt := models.ParseMediaType(mediaType)
		if !mt.Valid() {
			return response.Error(c, fiber.StatusBadRequest, "invalid type")
		}
		filters.Type = mt
	}
	if year := c.Query("year"); year != "" {
		y, err := strconv.Atoi(year)
		if err != nil {
			return response.Error(c, fiber.StatusBadRequest, "invalid year")
		}
		filters.Year = y
	}
	if q := strings.TrimSpace(c.Query("q")); q != "" {
		filters.Q = q
	}

	limit, offset := response.ClampPage(c.QueryInt("limit", defaultMediaPageSize), c.QueryInt("offset", 0), defaultMediaPageSize)

	ctx := c.UserContext()
	media, total, err := h.mediaRepo.FindAll(ctx, filters, limit, offset)
	if err != nil {
		log.Printf("FindAll: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch media")
	}
	if media == nil {
		media = []models.Media{}
	}

	return response.Paginated(c, media, total, limit, offset)
}

func (h *MediaHandler) Get(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, id)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	return c.JSON(media)
}

func (h *MediaHandler) Create(c *fiber.Ctx) error {
	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Title == "" {
		return response.Error(c, fiber.StatusBadRequest, "Title is required")
	}
	if req.FilePath == "" {
		return response.Error(c, fiber.StatusBadRequest, "FilePath is required")
	}
	if req.Type == "" || !models.ParseMediaType(string(req.Type)).Valid() {
		return response.Error(c, fiber.StatusBadRequest, "Invalid type")
	}

	ctx := c.UserContext()
	allowed, err := h.streamer.IsPathAllowed(ctx, req.FilePath)
	if err != nil {
		log.Printf("IsPathAllowed: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "File path is not within any registered library")
	}

	media := &models.Media{
		Title:       req.Title,
		Year:        req.Year,
		Description: req.Description,
		Type:        req.Type,
		FilePath:    req.FilePath,
	}

	if err := h.mediaRepo.Create(ctx, media); err != nil {
		log.Printf("Create: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create media")
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

func (h *MediaHandler) Update(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, id)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	var req CreateMediaRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.Title == "" {
		return response.Error(c, fiber.StatusBadRequest, "Title is required")
	}
	if req.FilePath == "" {
		return response.Error(c, fiber.StatusBadRequest, "FilePath is required")
	}
	// Тип обязателен как в Create: пустой type при Update молча игнорировался
	// репозиторием (контракт «только непустые поля») и затирал бы изменение.
	if req.Type == "" || !models.ParseMediaType(string(req.Type)).Valid() {
		return response.Error(c, fiber.StatusBadRequest, "Invalid type")
	}

	allowed, err := h.streamer.IsPathAllowed(ctx, req.FilePath)
	if err != nil {
		log.Printf("IsPathAllowed: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "File path is not within any registered library")
	}

	media.Title = req.Title
	media.Year = req.Year
	media.Description = req.Description
	media.Type = req.Type
	media.FilePath = req.FilePath

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		log.Printf("Update: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update media")
	}

	return c.JSON(media)
}

func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Get media record to find file path.
	media, err := h.mediaRepo.FindByID(ctx, id)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Delete the database record FIRST. If this fails the files remain on
	// disk (safe — they can be cleaned up later). If we deleted files first
	// and the DB delete failed, we'd be left with a "broken" record pointing
	// to non-existent files.
	if err := h.mediaRepo.Delete(ctx, id); err != nil {
		log.Printf("Delete: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete media")
	}

	// Физический файл удаляем ТОЛЬКО если он лежит в зарегистрированной
	// библиотеке — иначе Delete мог бы стереть произвольный файл системы
	// по пути, проставленному вручную (Create/Update проходят проверку,
	// но путь мог быть изменён в БД извне).
	if media.FilePath != "" {
		allowed, err := h.streamer.IsPathAllowed(ctx, media.FilePath)
		if err != nil {
			log.Printf("Delete: IsPathAllowed %s: %v", media.FilePath, err)
		} else if !allowed {
			log.Printf("Delete: skip removing %s — outside registered libraries", media.FilePath)
		} else if err := os.Remove(media.FilePath); err != nil && !os.IsNotExist(err) {
			log.Printf("Delete: remove file %s: %v", media.FilePath, err)
		}
	}

	// Delete thumbnail — файл ищется по ID, а не по ThumbnailURL
	// (в БД теперь относительный URL, а не путь ФС).
	if h.thumbSvc != nil {
		thumbPath := h.thumbSvc.GetPath(media.ID)
		if err := os.Remove(thumbPath); err != nil && !os.IsNotExist(err) {
			log.Printf("Delete: remove thumbnail %s: %v", thumbPath, err)
		}

		// Delete cover (все известные форматы).
		h.thumbSvc.RemoveCovers(media.ID)
	}

	return c.JSON(fiber.Map{"message": "Media deleted successfully"})
}

func (h *MediaHandler) CheckHash(c *fiber.Ctx) error {
	var req struct {
		Hash string `json:"hash"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Hash == "" {
		return response.Error(c, fiber.StatusBadRequest, "Hash is required")
	}

	ctx := c.UserContext()
	existing, err := h.mediaRepo.FindByHash(ctx, req.Hash)
	if err != nil {
		// Ошибка БД — это не "hash не найден": логируем и возвращаем 500,
		// чтобы клиент не принял сбой за отсутствие дубликата.
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("CheckHash: FindByHash: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to check hash")
		}
	}
	if existing != nil {
		return c.JSON(fiber.Map{
			"exists": true,
			"media": fiber.Map{
				"id":    existing.ID,
				"title": existing.Title,
			},
		})
	}

	return c.JSON(fiber.Map{"exists": false})
}

func (h *MediaHandler) Stream(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, id)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Разрешаем путь один раз и стримим ИМЕННО проверенный (резолвнутый)
	// путь: это закрывает TOCTOU-окно, где файл мог быть подменён между
	// проверкой и SendFile (например, через симлинк).
	allowed, resolvedPath, err := h.streamer.ResolveStreamPath(ctx, media.FilePath)
	if err != nil {
		log.Printf("Stream: ResolveStreamPath %s: %v", media.FilePath, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to validate file path")
	}
	if !allowed {
		return response.Error(c, fiber.StatusForbidden, "Access denied")
	}

	c.Set("Content-Type", services.MimeTypeByExt(strings.ToLower(filepath.Ext(resolvedPath))))

	// SendFile сам возвращает 404 (fiber.Error) для отсутствующего файла.
	// Отдельный os.Stat не нужен — он давал бы лишний системный вызов,
	// а fasthttp всё равно проверяет файл при отправке.
	if err := c.SendFile(resolvedPath); err != nil {
		var fiberErr *fiber.Error
		if errors.As(err, &fiberErr) && fiberErr.Code == fiber.StatusNotFound {
			// Не возвращаем текст ошибки SendFile — он содержит путь ФС.
			return response.Error(c, fiber.StatusNotFound, "File not found")
		}
		log.Printf("Stream: SendFile %s: %v", resolvedPath, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to stream file")
	}
	return nil
}

// maxBulkIDs — потолок числа ID в /api/media/bulk (DoS-защита).
const maxBulkIDs = 100

// Bulk возвращает медиа по списку ID из query-параметра ids=1,2,3.
func (h *MediaHandler) Bulk(c *fiber.Ctx) error {
	raw := c.Query("ids")
	if strings.TrimSpace(raw) == "" {
		return response.Error(c, fiber.StatusBadRequest, "ids parameter is required")
	}

	parts := strings.Split(raw, ",")
	if len(parts) > maxBulkIDs {
		return response.Error(c, fiber.StatusBadRequest, "too many ids (max "+strconv.Itoa(maxBulkIDs)+")")
	}

	seen := make(map[uint]struct{}, len(parts))
	ids := make([]uint, 0, len(parts))
	for _, p := range parts {
		id, err := strconv.ParseUint(strings.TrimSpace(p), 10, 64)
		if err != nil || id == 0 {
			return response.Error(c, fiber.StatusBadRequest, "invalid id in ids parameter")
		}
		u := uint(id)
		if _, dup := seen[u]; dup {
			continue
		}
		seen[u] = struct{}{}
		ids = append(ids, u)
	}

	media, err := h.mediaRepo.FindByIDs(c.UserContext(), ids)
	if err != nil {
		log.Printf("FindByIDs: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch media")
	}
	if media == nil {
		media = []models.Media{}
	}
	return c.JSON(fiber.Map{"items": media})
}
