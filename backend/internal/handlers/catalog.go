package handlers

import (
	"errors"
	"log"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"

	"gorm.io/gorm"
)

// CatalogHandler — глобальный каталог фильмов/сериалов/франшиз.
// Чтение доступно всем авторизованным, запись — только админу.
type CatalogHandler struct {
	works      *repository.WorkStore
	franchises *repository.FranchiseStore
}

func NewCatalogHandler(works *repository.WorkStore, franchises *repository.FranchiseStore) *CatalogHandler {
	return &CatalogHandler{works: works, franchises: franchises}
}

type createWorkRequest struct {
	Kind        models.WorkKind `json:"kind"`
	Title       string          `json:"title"`
	Description string          `json:"description"`
	CoverURL    string          `json:"cover_url"`
	Year        int             `json:"year"`
}

func (h *CatalogHandler) ListWorks(c *fiber.Ctx) error {
	kind := models.WorkKind(c.Query("kind"))
	tagIDs, err := parseTagIDs(c.Query("tag_ids"))
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "invalid tag_ids")
	}
	works, err := h.works.List(c.UserContext(), kind, tagIDs...)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(works)
}

func (h *CatalogHandler) GetMediaContext(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	result, err := h.works.GetMediaContext(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(result)
}

func (h *CatalogHandler) GetWork(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	work, err := h.works.Get(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(work)
}

func (h *CatalogHandler) CreateWork(c *fiber.Ctx) error {
	var req createWorkRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	work := models.Work{
		Kind: req.Kind, Title: req.Title, Description: req.Description,
		CoverURL: req.CoverURL, Year: req.Year,
	}
	// Тот же диапазон, что у метаданных медиа: иначе фильтры и сортировки
	// каталога получают год, которого не бывает.
	if work.Year != 0 && !metadata.IsValidYear(work.Year) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid year: must be between 1888 and current year + 2")
	}
	if err := h.works.Create(c.UserContext(), &work); err != nil {
		return h.mapError(c, err)
	}
	created, err := h.works.Get(c.UserContext(), work.ID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(created)
}

func (h *CatalogHandler) UpdateWork(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req struct {
		Title       *string `json:"title"`
		Description *string `json:"description"`
		CoverURL    *string `json:"cover_url"`
		Year        *int    `json:"year"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.Year != nil && *req.Year != 0 && !metadata.IsValidYear(*req.Year) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid year: must be between 1888 and current year + 2")
	}
	work, err := h.works.Update(c.UserContext(), id, repository.WorkPatch{
		Title: req.Title, Description: req.Description, CoverURL: req.CoverURL, Year: req.Year,
	})
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(work)
}

func (h *CatalogHandler) DeleteWork(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	if err := h.works.Delete(c.UserContext(), id); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) CreateSeason(c *fiber.Ctx) error {
	workID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req struct {
		SeasonNumber int    `json:"season_number"`
		Title        string `json:"title"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	season, err := h.works.CreateSeason(c.UserContext(), workID, req.SeasonNumber, req.Title)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(season)
}

func (h *CatalogHandler) UpdateSeason(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid season ID")
	}
	var req struct {
		SeasonNumber *int    `json:"season_number"`
		Title        *string `json:"title"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if _, err := h.works.UpdateSeason(c.UserContext(), id, repository.SeasonPatch{
		SeasonNumber: req.SeasonNumber, Title: req.Title,
	}); err != nil {
		return h.mapError(c, err)
	}
	season, err := h.works.GetSeason(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(season)
}

func (h *CatalogHandler) DeleteSeason(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid season ID")
	}
	if err := h.works.DeleteSeason(c.UserContext(), id); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) ReorderSeasons(c *fiber.Ctx) error {
	workID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req struct {
		SeasonIDs []uint `json:"season_ids"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.works.ReorderSeasons(c.UserContext(), workID, req.SeasonIDs); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

type addItemRequest struct {
	MediaID       uint `json:"media_id"`
	EpisodeNumber *int `json:"episode_number"`
}

func (h *CatalogHandler) AddEpisode(c *fiber.Ctx) error {
	seasonID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid season ID")
	}
	var req addItemRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.MediaID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_id is required")
	}
	if req.EpisodeNumber != nil && *req.EpisodeNumber < 0 {
		return response.Error(c, fiber.StatusBadRequest, "episode_number must be >= 0")
	}
	item, err := h.works.AddEpisode(c.UserContext(), seasonID, req.MediaID, req.EpisodeNumber)
	if err != nil {
		return h.mapError(c, err)
	}
	full, err := h.works.GetItem(c.UserContext(), item.ID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(full)
}

func (h *CatalogHandler) RemoveEpisode(c *fiber.Ctx) error {
	seasonID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid season ID")
	}
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	if err := h.works.RemoveEpisode(c.UserContext(), seasonID, mediaID); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) ReorderEpisodes(c *fiber.Ctx) error {
	seasonID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid season ID")
	}
	var req struct {
		ItemIDs []uint `json:"item_ids"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.works.ReorderSeasonItems(c.UserContext(), seasonID, req.ItemIDs); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) AddFilm(c *fiber.Ctx) error {
	workID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req struct {
		MediaID uint `json:"media_id"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.MediaID == 0 {
		return response.Error(c, fiber.StatusBadRequest, "media_id is required")
	}
	item, err := h.works.AddFilm(c.UserContext(), workID, req.MediaID)
	if err != nil {
		return h.mapError(c, err)
	}
	full, err := h.works.GetItem(c.UserContext(), item.ID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(full)
}

func (h *CatalogHandler) RemoveFilm(c *fiber.Ctx) error {
	workID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	if err := h.works.RemoveFilm(c.UserContext(), workID, mediaID); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) ReorderFilmItems(c *fiber.Ctx) error {
	workID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid work ID")
	}
	var req struct {
		ItemIDs []uint `json:"item_ids"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.works.ReorderWorkItems(c.UserContext(), workID, req.ItemIDs); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) ListFranchises(c *fiber.Ctx) error {
	tagIDs, err := parseTagIDs(c.Query("tag_ids"))
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "invalid tag_ids")
	}
	rows, err := h.franchises.List(c.UserContext(), tagIDs...)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(rows)
}

func (h *CatalogHandler) GetFranchise(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	row, err := h.franchises.Get(c.UserContext(), id)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(row)
}

func (h *CatalogHandler) CreateFranchise(c *fiber.Ctx) error {
	var req struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		CoverURL    string `json:"cover_url"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	row := models.Franchise{Name: req.Name, Description: req.Description, CoverURL: req.CoverURL}
	if err := h.franchises.Create(c.UserContext(), &row); err != nil {
		return h.mapError(c, err)
	}
	created, err := h.franchises.Get(c.UserContext(), row.ID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(created)
}

func (h *CatalogHandler) UpdateFranchise(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	var req struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		CoverURL    *string `json:"cover_url"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	row, err := h.franchises.Update(c.UserContext(), id, repository.FranchisePatch{
		Name: req.Name, Description: req.Description, CoverURL: req.CoverURL,
	})
	if err != nil {
		return h.mapError(c, err)
	}
	return c.JSON(row)
}

func (h *CatalogHandler) DeleteFranchise(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	if err := h.franchises.Delete(c.UserContext(), id); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) AddFranchiseEntry(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	var req struct {
		WorkID  *uint `json:"work_id"`
		MediaID *uint `json:"media_id"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if (req.WorkID == nil) == (req.MediaID == nil) ||
		(req.WorkID != nil && *req.WorkID == 0) ||
		(req.MediaID != nil && *req.MediaID == 0) {
		return response.Error(c, fiber.StatusBadRequest, "exactly one non-zero work_id or media_id is required")
	}
	entry, err := h.franchises.AddEntry(c.UserContext(), id, req.WorkID, req.MediaID)
	if err != nil {
		return h.mapError(c, err)
	}
	full, err := h.franchises.GetEntry(c.UserContext(), entry.ID)
	if err != nil {
		return h.mapError(c, err)
	}
	return c.Status(fiber.StatusCreated).JSON(full)
}

func (h *CatalogHandler) RemoveFranchiseEntry(c *fiber.Ctx) error {
	franchiseID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	entryID, err := parseIDParam(c, "entryId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid entry ID")
	}
	if err := h.franchises.RemoveEntry(c.UserContext(), franchiseID, entryID); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func (h *CatalogHandler) ReorderFranchiseEntries(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid franchise ID")
	}
	var req struct {
		EntryIDs []uint `json:"entry_ids"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if err := h.franchises.ReorderEntries(c.UserContext(), id, req.EntryIDs); err != nil {
		return h.mapError(c, err)
	}
	return c.SendStatus(fiber.StatusNoContent)
}

func parseTagIDs(raw string) ([]uint, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	var ids []uint
	for _, part := range strings.Split(raw, ",") {
		id, err := strconv.ParseUint(strings.TrimSpace(part), 10, 32)
		if err != nil || id == 0 {
			return nil, errors.New("invalid tag id")
		}
		ids = append(ids, uint(id))
	}
	return ids, nil
}

func (h *CatalogHandler) mapError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, gorm.ErrRecordNotFound):
		return response.Error(c, fiber.StatusNotFound, "Not found")
	case errors.Is(err, repository.ErrDuplicateWorkItem),
		errors.Is(err, repository.ErrDuplicateSeason),
		errors.Is(err, repository.ErrDuplicateFranchiseEntry),
		errors.Is(err, repository.ErrEpisodeAlreadyInSeason),
		errors.Is(err, repository.ErrMovieInFranchise),
		errors.Is(err, repository.ErrFranchiseMediaInWork):
		return response.Error(c, fiber.StatusConflict, err.Error())
	case errors.Is(err, repository.ErrInvalidWorkKind),
		errors.Is(err, repository.ErrWorkTitleRequired),
		errors.Is(err, repository.ErrSeasonNumberInvalid),
		errors.Is(err, repository.ErrNotSeries),
		errors.Is(err, repository.ErrNotFilmSeries),
		errors.Is(err, repository.ErrMediaNotVideo),
		errors.Is(err, repository.ErrMediaNotMovie),
		errors.Is(err, repository.ErrEpisodeInFilmSeries),
		errors.Is(err, repository.ErrEpisodeInFranchise),
		errors.Is(err, repository.ErrMovieInSeason),
		errors.Is(err, repository.ErrLastSeason),
		errors.Is(err, repository.ErrInvalidOrder),
		errors.Is(err, repository.ErrFranchiseEntryTarget),
		errors.Is(err, repository.ErrFranchiseWorkInvalid),
		errors.Is(err, repository.ErrFranchiseMediaInvalid),
		errors.Is(err, repository.ErrFranchiseNameRequired):
		return response.Error(c, fiber.StatusBadRequest, err.Error())
	default:
		log.Printf("Catalog: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Catalog operation failed")
	}
}
