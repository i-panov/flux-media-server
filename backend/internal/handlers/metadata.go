package handlers

import (
	"errors"
	"path/filepath"
	"strings"
	"unicode/utf8"

	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

// maxSearchQueryLen — предел длины запроса поиска по имени файла.
const maxSearchQueryLen = 256

type MetadataHandler struct {
	mediaRepo repository.MediaRepository
}

func NewMetadataHandler(mediaRepo repository.MediaRepository) *MetadataHandler {
	return &MetadataHandler{mediaRepo: mediaRepo}
}

type SearchResponse struct {
	Title string `json:"title"`
	Year  int    `json:"year"`
}

func (h *MetadataHandler) Search(c *fiber.Ctx) error {
	query := c.Query("q")
	if query == "" {
		return response.Error(c, fiber.StatusBadRequest, "Query parameter 'q' is required")
	}
	// Лимит считаем по символам, а не байтам: len() отсчитывал бы по 2 байта
	// на кириллицу и ложно отклонял запросы вдвое короче визуального лимита.
	if utf8.RuneCountInString(query) > maxSearchQueryLen {
		return response.Error(c, fiber.StatusBadRequest, "Query parameter 'q' is too long")
	}

	title, year := metadata.ParseFilename(query)

	return c.JSON(fiber.Map{
		"results": []SearchResponse{
			{Title: title, Year: year},
		},
	})
}

func (h *MetadataHandler) Refresh(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Parse only the filename, not the full path (otherwise directories
	// end up in the title).
	title, year := metadata.ParseFilename(filepath.Base(media.FilePath))

	media.Title = title
	media.Year = year

	if err := h.mediaRepo.Update(ctx, media); err != nil {
		return repoError(c, err, "Media not found", "Failed to update metadata")
	}

	return c.JSON(media)
}

func (h *MetadataHandler) Update(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "mediaId")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	// Pointer fields allow distinguishing "not provided" from "set to empty",
	// so values can also be cleared.
	var req struct {
		Title       *string   `json:"title"`
		Description *string   `json:"description"`
		Artists     *[]string `json:"artists"`
		Album       *string   `json:"album"`
		Genre       *string   `json:"genre"`
		Year        *int      `json:"year"`
		PosterURL   *string   `json:"poster_url"`
		Rating      *float64  `json:"rating"`
		Genres      *string   `json:"genres"`
		SourceURL   *string   `json:"source_url"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	// Ссылку валидируем до любых записей: при невалидном URL ничего
	// из присланного применяться не должно.
	var sourceURL *string
	if req.SourceURL != nil {
		normalized, err := metadata.NormalizeSourceURL(*req.SourceURL)
		if err != nil {
			msg := "Invalid source_url: must be an http(s) URL"
			if errors.Is(err, metadata.ErrSourceURLTooLong) {
				msg = "Invalid source_url: too long (max 2048 characters)"
			}
			return response.Error(c, fiber.StatusBadRequest, msg)
		}
		sourceURL = &normalized
	}

	if req.Title != nil {
		media.Title = *req.Title
	}
	if req.Description != nil {
		media.Description = *req.Description
	}
	if req.Artists != nil {
		// Build Artist slice from names; repository will find-or-create.
		media.Artists = make([]models.Artist, 0, len(*req.Artists))
		for _, name := range *req.Artists {
			name = strings.TrimSpace(name)
			if name != "" {
				media.Artists = append(media.Artists, models.Artist{Name: name})
			}
		}
	}
	if req.Album != nil {
		media.Album = *req.Album
	}
	if req.Genre != nil {
		media.Genre = *req.Genre
	}
	if req.Year != nil {
		if !metadata.IsValidYear(*req.Year) {
			return response.Error(c, fiber.StatusBadRequest, "Invalid year: must be between 1888 and current year + 2")
		}
		media.Year = *req.Year
	}

	if media.Metadata == nil {
		media.Metadata = &models.Metadata{}
	}
	if req.PosterURL != nil {
		media.Metadata.PosterURL = *req.PosterURL
	}
	if req.Rating != nil {
		if *req.Rating < 0 || *req.Rating > 10 {
			return response.Error(c, fiber.StatusBadRequest, "Invalid rating: must be between 0 and 10")
		}
		media.Metadata.Rating = *req.Rating
	}
	if req.Genres != nil {
		media.Metadata.Genres = *req.Genres
	}

	// Одна транзакция на всё: метаданные и ссылка пишутся вместе.
	// Пустая source_url означает «очистить» — общий Update такое
	// пропускает, поэтому ссылка идёт через UpdateWithSourceURL.
	// Сентinелы валидации маппятся в 400 и здесь тоже: репозиторий
	// перепроверяет ссылку как defense-in-depth, и его ответ не должен
	// превращаться в 500.
	if err := h.mediaRepo.UpdateWithSourceURL(ctx, media, sourceURL); err != nil {
		if errors.Is(err, metadata.ErrSourceURLTooLong) {
			return response.Error(c, fiber.StatusBadRequest, "Invalid source_url: too long (max 2048 characters)")
		}
		if errors.Is(err, metadata.ErrSourceURLInvalid) {
			return response.Error(c, fiber.StatusBadRequest, "Invalid source_url: must be an http(s) URL")
		}
		return repoError(c, err, "Media not found", "Failed to update metadata")
	}

	// Перечитываем для ответа: UpdatedAt и связанные данные после записи
	// свежее, чем в объекте до неё.
	media, err = h.mediaRepo.FindByID(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	return c.JSON(media)
}
