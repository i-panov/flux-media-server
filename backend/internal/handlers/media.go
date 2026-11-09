package handlers

import (
	"errors"
	"log"
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

// isValidMediaType возвращает true для пустой строки или валидного типа.
// Используется фильтром избранного: пустой тип означает «все типы».
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
	if rawArtist := c.Query("artist_id"); rawArtist != "" {
		// 32 бита: ID — uint, а на 32-битной сборке uint64-значение
		// молча обрезалось бы и могло отдать чужого артиста.
		artistID, err := strconv.ParseUint(rawArtist, 10, 32)
		if err != nil || artistID == 0 {
			return response.Error(c, fiber.StatusBadRequest, "invalid artist_id")
		}
		filters.ArtistID = uint(artistID)
	}
	// Порядок по id: по умолчанию старый (совместимо с прежним
	// поведением), sort=desc — новые сверху для мем-галереи.
	if sortOrder := c.Query("sort"); sortOrder != "" {
		switch sortOrder {
		case "asc":
			filters.SortDesc = false
		case "desc":
			filters.SortDesc = true
		default:
			return response.Error(c, fiber.StatusBadRequest, "invalid sort")
		}
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

func (h *MediaHandler) Delete(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()

	// Get media record for the response (path no longer needed here:
	// файл при уходе в корзину остаётся на диске для восстановления).
	if _, err := h.mediaRepo.FindByID(ctx, id); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Корзина: только флаг. Связи (избранное, прогресс, коллекции)
	// и файл целы — восстановление мгновенное. Навсегда — purge
	// в trash-хендлере (там же стирание файлов с диска).
	if err := h.mediaRepo.Delete(ctx, id); err != nil {
		log.Printf("Delete: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete media")
	}

	return c.JSON(fiber.Map{"message": "Media moved to trash"})
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
		// FindByHash возвращает не-nil пустую структуру вместе с
		// ErrRecordNotFound — проверять только existing != nil нельзя:
		// так любой новый файл отвечал «уже есть» (регрессия 759cf42).
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return c.JSON(fiber.Map{"exists": false})
		}
		// Ошибка БД — это не "hash не найден": логируем и возвращаем 500,
		// чтобы клиент не принял сбой за отсутствие дубликата.
		log.Printf("CheckHash: FindByHash: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to check hash")
	}
	return c.JSON(fiber.Map{
		"exists": true,
		// Корзина видна дедупу: клиент различит «уже в библиотеке»
		// и «лежит в корзине — предложи восстановить».
		"trashed": existing.DeletedAt.Valid,
		"media": fiber.Map{
			"id":    existing.ID,
			"title": existing.Title,
		},
	})
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

	// Счётчик стартов для админской чистки оригиналов. Ошибка записи
	// стрим не роняет — только лог. Считаем только старты с начала:
	// запросы с Range (сики/ретраи плеера) аналитику не накручивают.
	if c.Get("Range") == "" {
		if err := h.mediaRepo.IncrementViews(ctx, id); err != nil {
			log.Printf("Stream: increment views %d: %v", id, err)
		}
	}

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
