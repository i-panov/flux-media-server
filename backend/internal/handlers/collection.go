package handlers

import (
	"log"

	"github.com/gofiber/fiber/v2"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
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
	Name string `json:"name"`
	Type string `json:"type"`
}

func (h *CollectionHandler) Create(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
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
		req.Type = "video"
	}

	ctx := c.UserContext()
	col := &models.Collection{
		UserID: userID,
		Name:   req.Name,
		Type:   req.Type,
	}

	if err := h.colRepo.Create(ctx, col); err != nil {
		log.Printf("Create collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create collection")
	}

	return c.Status(fiber.StatusCreated).JSON(col)
}

func (h *CollectionHandler) List(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
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
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	col, err := h.colRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Collection not found")
	}

	if col.UserID != userID {
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	var req CreateCollectionRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Name != "" {
		col.Name = req.Name
	}

	if err := h.colRepo.Update(ctx, col); err != nil {
		log.Printf("Update collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update collection")
	}

	return c.JSON(col)
}

func (h *CollectionHandler) Delete(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	id, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	ctx := c.UserContext()
	col, err := h.colRepo.FindByID(ctx, uint(id))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Collection not found")
	}

	if col.UserID != userID {
		return response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	if err := h.colRepo.Delete(ctx, uint(id)); err != nil {
		log.Printf("Delete collection: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to delete collection")
	}

	return c.JSON(fiber.Map{"message": "Collection deleted"})
}

type AddItemRequest struct {
	MediaID uint `json:"media_id"`
}

func (h *CollectionHandler) AddItem(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
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
	if _, err := h.getOwnedCollection(c, uint(collectionID)); err != nil {
		return err
	}

	// Verify media exists
	if _, err := h.mediaRepo.FindByID(ctx, req.MediaID); err != nil {
		return response.Error(c, fiber.StatusNotFound, "Media not found")
	}

	item := &models.CollectionItem{
		CollectionID: uint(collectionID),
		MediaID:      req.MediaID,
	}

	if err := h.itemRepo.Add(ctx, item); err != nil {
		log.Printf("Add collection item: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to add item to collection")
	}

	return c.Status(fiber.StatusCreated).JSON(item)
}

func (h *CollectionHandler) RemoveItem(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	mediaID, err := c.ParamsInt("mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	// Only the owner may modify a collection.
	if _, err := h.getOwnedCollection(c, uint(collectionID)); err != nil {
		return err
	}

	ctx := c.UserContext()

	if err := h.itemRepo.Remove(ctx, uint(collectionID), uint(mediaID)); err != nil {
		log.Printf("Remove collection item: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to remove item")
	}

	return c.JSON(fiber.Map{"message": "Item removed"})
}

func (h *CollectionHandler) ListItems(c *fiber.Ctx) error {
	collectionID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid collection ID")
	}

	// Only the owner may view a collection's contents.
	if _, err := h.getOwnedCollection(c, uint(collectionID)); err != nil {
		return err
	}

	ctx := c.UserContext()
	// Return full media objects so clients don't need N+1 requests.
	media, err := h.itemRepo.FindMediaByCollection(ctx, uint(collectionID))
	if err != nil {
		log.Printf("List collection items: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch items")
	}

	return c.JSON(media)
}

// getOwnedCollection loads the collection and verifies it belongs to the
// current user. On failure it writes the appropriate error response.
func (h *CollectionHandler) getOwnedCollection(c *fiber.Ctx, collectionID uint) (*models.Collection, error) {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return nil, response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	col, err := h.colRepo.FindByID(c.UserContext(), collectionID)
	if err != nil {
		return nil, response.Error(c, fiber.StatusNotFound, "Collection not found")
	}

	if col.UserID != userID {
		return nil, response.Error(c, fiber.StatusForbidden, "Not your collection")
	}

	return col, nil
}
