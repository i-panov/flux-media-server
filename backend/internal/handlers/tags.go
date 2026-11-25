package handlers

import (
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type TagHandler struct {
	tags *repository.TagStore
}

func NewTagHandler(tags *repository.TagStore) *TagHandler {
	return &TagHandler{tags: tags}
}

type tagRequest struct {
	Group string `json:"group"`
	Slug  string `json:"slug"`
	Name  string `json:"name"`
}

type tagIDsRequest struct {
	TagIDs []uint `json:"tag_ids"`
}

func (h *TagHandler) mapError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, repository.ErrTagGroupInvalid),
		errors.Is(err, repository.ErrTagSlugRequired),
		errors.Is(err, repository.ErrTagNameRequired),
		errors.Is(err, repository.ErrTagGroupImmutable):
		return response.Error(c, fiber.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrTagSlugTaken):
		return response.Error(c, fiber.StatusConflict, err.Error())
	case errors.Is(err, repository.ErrTooManyFormatTags),
		errors.Is(err, repository.ErrFormatOnWork),
		errors.Is(err, repository.ErrTagsForImage):
		return response.Error(c, fiber.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrTagNotFound),
		errors.Is(err, gorm.ErrRecordNotFound):
		return response.Error(c, fiber.StatusNotFound, "Tag or entity not found")
	default:
		return response.Error(c, fiber.StatusInternalServerError, "Failed to update tags")
	}
}

func (h *TagHandler) List(c *fiber.Ctx) error {
	group := strings.TrimSpace(c.Query("group"))
	rows, err := h.tags.List(c.UserContext(), group)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) Create(c *fiber.Ctx) error {
	var req tagRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	tag := models.Tag{Group: req.Group, Slug: req.Slug, Name: req.Name}
	if err := h.tags.Create(c.UserContext(), &tag); err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(tag)
}

func (h *TagHandler) Update(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid tag ID")
	}
	var req tagRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	tag, err := h.tags.Update(c.UserContext(), id, req.Group, req.Slug, req.Name)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(tag)
}

func (h *TagHandler) Delete(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid tag ID")
	}
	if err := h.tags.Delete(c.UserContext(), id); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

type bulkTagsRequest struct {
	MediaIDs []uint `json:"media_ids"`
	TagID    uint   `json:"tag_id"`
	Add      bool   `json:"add"`
}

// maxBulkTagMedia ограничивает /tags/bulk: репозиторий делает вставку на
// каждый ID в одной транзакции, и 4 МБ тела держали бы писательский лок
// SQLite десятками тысяч вставок.
const maxBulkTagMedia = 500

func (h *TagHandler) BulkMediaTags(c *fiber.Ctx) error {
	var req bulkTagsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.TagID == 0 || len(req.MediaIDs) == 0 {
		return response.Error(c, fiber.StatusBadRequest, "tag_id and media_ids are required")
	}
	if len(req.MediaIDs) > maxBulkTagMedia {
		return response.Error(c, fiber.StatusBadRequest, "too many media_ids (max 500)")
	}
	affected, err := h.tags.BulkMediaTags(c.UserContext(), req.MediaIDs, req.TagID, req.Add)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(fiber.Map{"affected": affected})
}

func (h *TagHandler) MediaTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	rows, err := h.tags.MediaTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) SetMediaTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	var req tagIDsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.tags.SetMediaTags(c.UserContext(), id, req.TagIDs); err != nil {
		return h.mapError(c, err)
	}
	rows, err := h.tags.MediaTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) WorkTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	rows, err := h.tags.WorkTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) SetWorkTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req tagIDsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.tags.SetWorkTags(c.UserContext(), id, req.TagIDs); err != nil {
		return h.mapError(c, err)
	}
	rows, err := h.tags.WorkTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) FranchiseTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	rows, err := h.tags.FranchiseTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}

func (h *TagHandler) SetFranchiseTags(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	var req tagIDsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.tags.SetFranchiseTags(c.UserContext(), id, req.TagIDs); err != nil {
		return h.mapError(c, err)
	}
	rows, err := h.tags.FranchiseTags(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	if rows == nil {
		rows = []models.Tag{}
	}
	return c.JSON(rows)
}
