package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"

	"gorm.io/gorm"
)

type CollectionHandler struct {
	colRepo   repository.CollectionRepository
	itemRepo  repository.CollectionItemRepository
	mediaRepo repository.MediaRepository
}

func NewCollectionHandler(
	colRepo repository.CollectionRepository,
	itemRepo repository.CollectionItemRepository,
	mediaRepo repository.MediaRepository,
) *CollectionHandler {
	return &CollectionHandler{colRepo: colRepo, itemRepo: itemRepo, mediaRepo: mediaRepo}
}

type CreateCollectionRequest struct {
	Name     string           `json:"name"`
	Type     models.MediaType `json:"type"`
	ParentID *uint            `json:"parent_id"`
}

func (h *CollectionHandler) Create(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	var req CreateCollectionRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}
	if req.Type == "" {
		req.Type = models.MediaTypeVideo
	}
	if !models.ParseMediaType(string(req.Type)).Valid() {
		return response.Error(c, fiber.StatusBadRequest, "Invalid type")
	}

	ctx := c.UserContext()
	col := &models.Collection{
		UserID: userID,
		Name:   req.Name,
		Type:   req.Type,
	}

	// Родитель — в той же транзакции, что и Create (CreateWithParent):
	// при отказе проверок сироты-корня в БД не остаётся.
	if req.ParentID != nil {
		if err := h.colRepo.CreateWithParent(ctx, col, *req.ParentID); err != nil {
			return h.mapParentError(c, err)
		}
	} else if err := h.colRepo.Create(ctx, col); err != nil {
		log.Printf("Create collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create collection")
	}

	return c.Status(fiber.StatusCreated).JSON(col)
}

func (h *CollectionHandler) List(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	ctx := c.UserContext()
	cols, err := h.colRepo.FindByUser(ctx, userID)
	if err != nil {
		log.Printf("List collections: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch collections")
	}

	return c.JSON(cols)
}

func (h *CollectionHandler) Update(c *fiber.Ctx) error {
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

	var req CreateCollectionRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	// parent_id — три состояния: ключа нет (не трогаем — иначе каждое
	// переименование сбрасывало бы в корень), null (в корень), N
	// (под родителя). *uint не различает «нет» и «null», поэтому
	// наличие ключа проверяем отдельным разбором (BodyParser
	// перечитывает закешированное тело).
	var raw map[string]any
	if err := c.BodyParser(&raw); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	var patch repository.CollectionPatch
	if req.Name != "" {
		patch.Name = &req.Name
	}
	if req.Type != "" {
		parsed := models.ParseMediaType(string(req.Type))
		if !parsed.Valid() {
			return response.Error(c, fiber.StatusBadRequest, "Invalid type")
		}
		patch.Type = &parsed
	}
	if _, present := raw["parent_id"]; present {
		if req.ParentID == nil {
			patch.MoveToRoot = true
		} else {
			patch.ParentID = req.ParentID
		}
	}

	// Одна транзакция на всё: переезд и переименование не разъезжаются.
	updated, err := h.colRepo.Patch(ctx, col.ID, patch)
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrCycle):
			return response.Error(c, fiber.StatusBadRequest, "Move would create a cycle")
		case errors.Is(err, repository.ErrCrossUser):
			return response.Error(c, fiber.StatusForbidden, "Not your collection")
		case errors.Is(err, repository.ErrCrossType):
			return response.Error(c, fiber.StatusBadRequest, "Parent collection has different type")
		case errors.Is(err, repository.ErrTypeChangeBlocked):
			return response.Error(c, fiber.StatusBadRequest, "Cannot change type while collection has children or items")
		default:
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return response.Error(c, fiber.StatusNotFound, "Parent collection not found")
			}
			log.Printf("Patch collection: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to update collection")
		}
	}

	return c.JSON(updated)
}

// mapParentError переводит ошибки привязки родителя в HTTP-ответы.
func (h *CollectionHandler) mapParentError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, repository.ErrCycle):
		return response.Error(c, fiber.StatusBadRequest, "Move would create a cycle")
	case errors.Is(err, repository.ErrCrossUser):
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	case errors.Is(err, repository.ErrCrossType):
		return response.Error(c, fiber.StatusBadRequest, "Parent collection has different type")
	default:
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Parent collection not found")
		}
		log.Printf("Move collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to move collection")
	}
}

func (h *CollectionHandler) Delete(c *fiber.Ctx) error {
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

	if err := h.colRepo.Delete(ctx, id); err != nil {
		log.Printf("Delete collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete collection")
	}

	return c.JSON(fiber.Map{"message": "Collection deleted"})
}

type AddItemRequest struct {
	MediaID uint `json:"media_id"`
}

func (h *CollectionHandler) AddItem(c *fiber.Ctx) error {
	collectionID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	var req AddItemRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.MediaID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_id is required")
	}

	ctx := c.UserContext()

	// Only the owner may modify a collection.
	if _, ok := h.getOwnedCollection(c, collectionID); !ok {
		return nil
	}

	// Verify media exists
	if _, err := h.mediaRepo.FindByID(ctx, req.MediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Позиция и проверка дубликата выполняются атомарно в репозитории:
	// параллельные добавления больше не дают 500 на UNIQUE-индексе.
	item, err := h.itemRepo.AddItemAtomic(ctx, collectionID, req.MediaID)
	if err != nil {
		if errors.Is(err, repository.ErrDuplicateItem) {
			return response.Error(c, fiber.StatusConflict, "Media already in collection")
		}
		log.Printf("AddItemAtomic: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add item to collection")
	}

	return c.Status(fiber.StatusCreated).JSON(item)
}

type MoveItemRequest struct {
	MediaID        uint `json:"media_id"`
	ToCollectionID uint `json:"to_collection_id"`
}

// MoveItem атомарно переносит элемент между коллекциями одного типа
// и одного владельца. Дубликат в целевой — 409 без потери исходника
// (репозиторий вставляет раньше, чем удаляет).
func (h *CollectionHandler) MoveItem(c *fiber.Ctx) error {
	sourceID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	var req MoveItemRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.MediaID == 0 || req.ToCollectionID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_id and to_collection_id are required")
	}

	source, ok := h.getOwnedCollection(c, sourceID)
	if !ok {
		return nil
	}
	target, ok := h.getOwnedCollection(c, req.ToCollectionID)
	if !ok {
		return nil
	}
	if source.Type != target.Type {
		return response.Error(c, fiber.StatusBadRequest, "Collections have different types")
	}

	ctx := c.UserContext()
	if _, err := h.mediaRepo.FindByID(ctx, req.MediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	item, err := h.itemRepo.MoveItemAtomic(ctx, sourceID, req.ToCollectionID, req.MediaID)
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrDuplicateItem):
			return response.Error(c, fiber.StatusConflict, "Media already in target collection")
		case errors.Is(err, repository.ErrNotMember):
			return response.Error(c, fiber.StatusNotFound, "Media not in source collection")
		case errors.Is(err, repository.ErrSameCollection):
			return response.Error(c, fiber.StatusBadRequest, "Source and target are the same collection")
		default:
			log.Printf("MoveItemAtomic: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to move item")
		}
	}

	return c.JSON(item)
}

func (h *CollectionHandler) RemoveItem(c *fiber.Ctx) error {
	collectionID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	// Only the owner may modify a collection.
	if _, ok := h.getOwnedCollection(c, collectionID); !ok {
		return nil
	}

	ctx := c.UserContext()

	if _, err := h.itemRepo.Remove(ctx, collectionID, mediaID); err != nil {
		log.Printf("Remove collection item: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove item")
	}

	return c.JSON(fiber.Map{"message": "Item removed"})
}

func (h *CollectionHandler) ListItems(c *fiber.Ctx) error {
	collectionID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	// Only the owner may view a collection's contents.
	if _, ok := h.getOwnedCollection(c, collectionID); !ok {
		return nil
	}

	ctx := c.UserContext()
	// Return full media objects so clients don't need N+1 requests.
	media, err := h.itemRepo.FindMediaByCollection(ctx, collectionID)
	if err != nil {
		log.Printf("List collection items: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch items")
	}
	if media == nil {
		media = []models.Media{}
	}

	return c.JSON(media)
}

// maxBulkItems — потолок числа элементов в групповой операции.
// Сезон из 20-40 серий укладывается; тысячи id в одном запросе — это
// уже не «выделил и нажал», а злоупотребление.
const maxBulkItems = 500

// BulkItemsRequest — набор медиа для групповой операции.
type BulkItemsRequest struct {
	MediaIDs []uint `json:"media_ids"`
}

// BulkMoveItemsRequest — групповой перенос между коллекциями.
type BulkMoveItemsRequest struct {
	MediaIDs       []uint `json:"media_ids"`
	ToCollectionID uint   `json:"to_collection_id"`
}

// BulkItemsResult — итог групповой операции.
//
// Частичный успех — норма, а не ошибка: часть элементов может уже
// лежать в целевой коллекции (или её не быть), и из-за одного такого
// элемента весь запрос падать не должен.
type BulkItemsResult struct {
	Added   []uint `json:"added"`
	Moved   []uint `json:"moved"`
	Removed []uint `json:"removed"`
	Skipped []uint `json:"skipped"`
}

// parseBulkItems разбирает тело групповой операции: список непустой и
// не длиннее maxBulkItems.
//
// Второе значение — «можно продолжать»: false означает, что ответ уже
// записан (400) и обработчик обязан остановиться. Раньше здесь
// возвращалась ошибка, а response.Error отдаёт nil после записи
// ответа — обработчик продолжал работу и затирал тело 400 результатом
// операции.
func parseBulkItems(c *fiber.Ctx) ([]uint, bool) {
	var req BulkItemsRequest
	if err := c.BodyParser(&req); err != nil {
		response.Error(c, fiber.StatusBadRequest, "Invalid request body")
		return nil, false
	}
	if len(req.MediaIDs) == 0 {
		response.Error(c, fiber.StatusBadRequest, "media_ids is required")
		return nil, false
	}
	if len(req.MediaIDs) > maxBulkItems {
		response.Error(c, fiber.StatusBadRequest, "too many media_ids")
		return nil, false
	}
	return req.MediaIDs, true
}

// AddItemsBulk добавляет несколько медиа в коллекцию за один запрос.
//
// Групповая операция нужна для сезонов: раскладывать их по коллекции
// по одному файлу — рутина на десятки запросов.
func (h *CollectionHandler) AddItemsBulk(c *fiber.Ctx) error {
	collectionID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}
	mediaIDs, ok := parseBulkItems(c)
	if !ok {
		return nil
	}
	if _, ok := h.getOwnedCollection(c, collectionID); !ok {
		return nil
	}

	ctx := c.UserContext()
	result := BulkItemsResult{Added: []uint{}, Skipped: []uint{}}
	for _, mediaID := range mediaIDs {
		if mediaID == 0 {
			continue
		}
		if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
			result.Skipped = append(result.Skipped, mediaID)
			continue
		}
		if _, err := h.itemRepo.AddItemAtomic(ctx, collectionID, mediaID); err != nil {
			// Дубликат в коллекции — не ошибка запроса, а пропуск.
			if !errors.Is(err, repository.ErrDuplicateItem) {
				log.Printf("AddItemAtomic (bulk): %v", err)
			}
			result.Skipped = append(result.Skipped, mediaID)
			continue
		}
		result.Added = append(result.Added, mediaID)
	}

	return c.JSON(result)
}

// MoveItemsBulk переносит несколько элементов из своей коллекции в другую.
//
// Порядок внутри репозитория (вставка в цель, потом удаление из
// источника) гарантирует, что дубликат в цели не приводит к потере
// элемента из источника.
func (h *CollectionHandler) MoveItemsBulk(c *fiber.Ctx) error {
	sourceID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	var req BulkMoveItemsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if len(req.MediaIDs) == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_ids is required")
	}
	if len(req.MediaIDs) > maxBulkItems {
		return response.Error(c, fiber.StatusBadRequest, "too many media_ids")
	}
	if req.ToCollectionID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "to_collection_id is required")
	}

	source, ok := h.getOwnedCollection(c, sourceID)
	if !ok {
		return nil
	}
	target, ok := h.getOwnedCollection(c, req.ToCollectionID)
	if !ok {
		return nil
	}
	if source.Type != target.Type {
		return response.Error(c, fiber.StatusBadRequest, "Collections have different types")
	}

	ctx := c.UserContext()
	result := BulkItemsResult{Moved: []uint{}, Skipped: []uint{}}
	for _, mediaID := range req.MediaIDs {
		if mediaID == 0 {
			continue
		}
		item, err := h.itemRepo.MoveItemAtomic(ctx, sourceID, req.ToCollectionID, mediaID)
		if err != nil {
			// Не член источника — тоже пропуск, а не падение всего запроса.
			if !errors.Is(err, repository.ErrNotMember) &&
				!errors.Is(err, repository.ErrDuplicateItem) {
				log.Printf("MoveItemAtomic (bulk): %v", err)
			}
			result.Skipped = append(result.Skipped, mediaID)
			continue
		}
		result.Moved = append(result.Moved, item.MediaID)
	}

	return c.JSON(result)
}

// RemoveItemsBulk убирает несколько элементов из коллекции.
func (h *CollectionHandler) RemoveItemsBulk(c *fiber.Ctx) error {
	collectionID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}
	mediaIDs, ok := parseBulkItems(c)
	if !ok {
		return nil
	}
	if _, ok := h.getOwnedCollection(c, collectionID); !ok {
		return nil
	}

	ctx := c.UserContext()
	result := BulkItemsResult{Removed: []uint{}, Skipped: []uint{}}
	for _, mediaID := range mediaIDs {
		if mediaID == 0 {
			continue
		}
		affected, err := h.itemRepo.Remove(ctx, collectionID, mediaID)
		if err != nil {
			log.Printf("Remove collection item (bulk): %v", err)
			result.Skipped = append(result.Skipped, mediaID)
			continue
		}
		// Элемента в коллекции не было — это «пропущено», а не «удалено».
		if affected == 0 {
			result.Skipped = append(result.Skipped, mediaID)
			continue
		}
		result.Removed = append(result.Removed, mediaID)
	}

	return c.JSON(result)
}

// getOwnedCollection loads the collection and verifies it belongs to the
// current user.
//
// The second return value says whether the caller may continue. false
// means the response has already been written (401/403/404) and the
// handler must stop.
//
// It used to be an error, and that was a hole: response.Error returns nil
// after a successful write, so the `err != nil` check never fired and the
// handler went on to modify a collection it had just refused — the client
// got 403 while the data changed underneath it.
func (h *CollectionHandler) getOwnedCollection(c *fiber.Ctx, collectionID uint) (*models.Collection, bool) {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
		return nil, false
	}

	col, err := h.colRepo.FindByID(c.UserContext(), collectionID)
	if err != nil {
		repoError(c, err, "Collection not found", "Failed to fetch collection")
		return nil, false
	}

	if col.UserID != userID {
		response.Error(c, fiber.StatusForbidden, "Not your collection")
		return nil, false
	}

	return col, true
}
