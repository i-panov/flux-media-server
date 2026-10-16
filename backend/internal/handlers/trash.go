package handlers

import (
	"context"
	"errors"
	"log"
	"os"

	"github.com/gofiber/fiber/v2"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"

	"gorm.io/gorm"
)

// TrashHandler — корзина: список, восстановление, снос навсегда.
// Медиа глобальные, коллекции — персональные (владение как везде).
type TrashHandler struct {
	mediaRepo repository.MediaRepository
	colRepo   repository.CollectionRepository
	streamer  services.StreamerInterface
	thumbSvc  *services.ThumbnailService
}

func NewTrashHandler(
	mediaRepo repository.MediaRepository,
	colRepo repository.CollectionRepository,
	streamer services.StreamerInterface,
	thumbSvc *services.ThumbnailService,
) *TrashHandler {
	return &TrashHandler{
		mediaRepo: mediaRepo,
		colRepo:   colRepo,
		streamer:  streamer,
		thumbSvc:  thumbSvc,
	}
}

type TrashListResponse struct {
	Collections []models.Collection `json:"collections"`
	Media       []models.Media      `json:"media"`
}

// List отдаёт корзину плоским списком (вложенности внутри нет).
func (h *TrashHandler) List(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	ctx := c.UserContext()
	cols, err := h.colRepo.TrashedCollections(ctx, userID, 0, 0)
	if err != nil {
		log.Printf("Trash list collections: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch trash")
	}
	if cols == nil {
		cols = []models.Collection{}
	}
	media, err := h.mediaRepo.TrashedMedia(ctx, 0, 0)
	if err != nil {
		log.Printf("Trash list media: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch trash")
	}
	if media == nil {
		media = []models.Media{}
	}

	return c.JSON(TrashListResponse{Collections: cols, Media: media})
}

// RestoreMedia возвращает медиа из корзины. Файл всё время лежал
// на диске — пересканировать не нужно.
func (h *TrashHandler) RestoreMedia(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	if err := h.mediaRepo.RestoreMedia(c.UserContext(), id); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) || errors.Is(err, repository.ErrNotInTrash) {
			return response.Error(c, fiber.StatusNotFound, "Media not found in trash")
		}
		if errors.Is(err, repository.ErrPathConflict) {
			return response.Error(c, fiber.StatusConflict, "Live media already exists at this path")
		}
		log.Printf("Trash restore media: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to restore media")
	}

	return c.JSON(fiber.Map{"message": "Media restored"})
}

// RestoreCollection возвращает поддерево из корзины; при недоступном
// родителе коллекция встаёт в корень.
func (h *TrashHandler) RestoreCollection(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	if err := h.findTrashedCollection(c, userID, id); err != nil {
		return err
	}

	if err := h.colRepo.RestoreCollection(ctx, id); err != nil {
		log.Printf("Trash restore collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to restore collection")
	}

	return c.JSON(fiber.Map{"message": "Collection restored"})
}

// PurgeMedia сносит медиа навсегда: строка (hard), связи каскадом,
// файл и обложки с диска — воскрешать нечего, место свободно.
func (h *TrashHandler) PurgeMedia(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindTrashedMedia(ctx, id)
	if err != nil {
		return h.mapTrashError(c, err)
	}

	if err := h.mediaRepo.PurgeMedia(ctx, id); err != nil {
		log.Printf("Trash purge media: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to purge media")
	}

	h.removeMediaFiles(ctx, media)

	return c.JSON(fiber.Map{"message": "Media permanently deleted"})
}

// PurgeCollection сносит поддерево навсегда (элементы + строки).
// Файлов у коллекций нет — с диска стирать нечего.
func (h *TrashHandler) PurgeCollection(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	if err := h.findTrashedCollection(c, userID, id); err != nil {
		return err
	}

	if err := h.colRepo.PurgeCollection(ctx, id); err != nil {
		log.Printf("Trash purge collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to purge collection")
	}

	return c.JSON(fiber.Map{"message": "Collection permanently deleted"})
}

// Empty вычищает всю корзину: коллекции пользователя и все медиа.
// Батчами по 200: грузить всю корзину в память нельзя, а атомарность
// на файлы всё равно не распространяется (os.Remove вне транзакций).
// Ошибка батча прерывает очистку — уже снесённое не воскресает,
// остаток добирается повторным вызовом.
func (h *TrashHandler) Empty(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	ctx := c.UserContext()
	for {
		cols, err := h.colRepo.TrashedCollections(ctx, userID, 200, 0)
		if err != nil {
			log.Printf("Trash empty collections: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to empty trash")
		}
		if len(cols) == 0 {
			break
		}
		for i := range cols {
			if err := h.colRepo.PurgeCollection(ctx, cols[i].ID); err != nil {
				log.Printf("Trash empty purge collection %d: %v", cols[i].ID, err)
				return response.Error(c, fiber.StatusInternalServerError, "Failed to empty trash")
			}
			if i >= 199 {
				break
			}
		}
	}

	for {
		media, err := h.mediaRepo.TrashedMedia(ctx, 200, 0)
		if err != nil {
			log.Printf("Trash empty media: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to empty trash")
		}
		if len(media) == 0 {
			break
		}
		for i := range media {
			if err := h.mediaRepo.PurgeMedia(ctx, media[i].ID); err != nil {
				log.Printf("Trash empty purge media %d: %v", media[i].ID, err)
				return response.Error(c, fiber.StatusInternalServerError, "Failed to empty trash")
			}
			h.removeMediaFiles(ctx, &media[i])
		}
	}

	return c.JSON(fiber.Map{"message": "Trash emptied"})
}

// Stats отдаёт живые счётчики поддерева коллекции для confirm-диалога
// («2 подколлекции и 24 файла» вместо слепого удаления).
func (h *TrashHandler) Stats(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	col, err := h.colRepo.FindByID(ctx, id)
	if err != nil {
		return repoError(c, err, "Collection not found", "Failed to fetch collection")
	}
	if col.UserID != userID {
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	collections, items, err := h.colRepo.SubtreeStats(ctx, id)
	if err != nil {
		log.Printf("Trash stats: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch stats")
	}

	return c.JSON(fiber.Map{"subcollections": collections, "items": items})
}

// trashedMedia грузит trashed-строку медиа (живые сюда не попадают:
// purge и restore работают только с корзиной).
// findTrashedCollection проверяет, что коллекция в корзине пользователя.
func (h *TrashHandler) findTrashedCollection(c *fiber.Ctx, userID, id uint) error {
	_, err := h.colRepo.FindTrashedCollection(c.UserContext(), userID, id)
	if err != nil {
		return h.mapTrashError(c, err)
	}
	return nil
}

// mapTrashError переводит ошибки корзины в ответы: чужое и живое
// не различаем — везде 404, чтобы не раскрывать чужие данные.
func (h *TrashHandler) mapTrashError(c *fiber.Ctx, err error) error {
	if errors.Is(err, gorm.ErrRecordNotFound) || errors.Is(err, repository.ErrNotInTrash) {
		return response.Error(c, fiber.StatusNotFound, "Not found in trash")
	}
	log.Printf("Trash: %v", err)
	return response.Error(c, fiber.StatusInternalServerError, "Trash operation failed")
}

// removeMediaFiles стирает файл и обложки — только внутри
// зарегистрированных библиотек (та же защита, что была в Delete).
func (h *TrashHandler) removeMediaFiles(ctx context.Context, media *models.Media) {
	if media.FilePath != "" {
		allowed, err := h.streamer.IsPathAllowed(ctx, media.FilePath)
		if err != nil {
			log.Printf("Trash purge: IsPathAllowed %s: %v", media.FilePath, err)
		} else if !allowed {
			log.Printf("Trash purge: skip removing %s — outside registered libraries", media.FilePath)
		} else if err := os.Remove(media.FilePath); err != nil && !os.IsNotExist(err) {
			log.Printf("Trash purge: remove file %s: %v", media.FilePath, err)
		}
	}
	if h.thumbSvc != nil {
		if thumbPath := h.thumbSvc.GetPath(media.ID); thumbPath != "" {
			if err := os.Remove(thumbPath); err != nil && !os.IsNotExist(err) {
				log.Printf("Trash purge: remove thumbnail %s: %v", thumbPath, err)
			}
		}
		h.thumbSvc.RemoveCovers(media.ID)
	}
}
