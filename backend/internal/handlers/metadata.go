package handlers

import (
	"errors"
	"path/filepath"
	"unicode/utf8"

	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
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

	// Постер валидируем тем же валидатором, что source_url: http(s),
	// без credentials. Пустая строка — валидное «очистить».
	var posterURL *string
	if req.PosterURL != nil {
		normalized, err := metadata.NormalizeSourceURL(*req.PosterURL)
		if err != nil {
			msg := "Invalid poster_url: must be an http(s) URL"
			if errors.Is(err, metadata.ErrSourceURLTooLong) {
				msg = "Invalid poster_url: too long (max 2048 characters)"
			}
			return response.Error(c, fiber.StatusBadRequest, msg)
		}
		posterURL = &normalized
	}

	// 0 — валидное «год неизвестен»: редактор должен уметь очищать поле.
	if req.Year != nil && *req.Year != 0 && !metadata.IsValidYear(*req.Year) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid year: must be between 1888 and current year + 2")
	}
	if req.Rating != nil && (*req.Rating < 0 || *req.Rating > 10) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid rating: must be between 0 and 10")
	}

	patch := repository.MetadataPatch{
		Title:       req.Title,
		Description: req.Description,
		Artists:     req.Artists,
		Album:       req.Album,
		Genre:       req.Genre,
		Year:        req.Year,
		SourceURL:   sourceURL,
		PosterURL:   posterURL,
		Rating:      req.Rating,
		Genres:      req.Genres,
	}

	ctx := c.UserContext()
	media, err := h.mediaRepo.PatchMetadata(ctx, mediaID, patch)
	if err != nil {
		// Сентинелы валидации репозиторий перепроверяет как
		// defense-in-depth — его ответ не должен превращаться в 500.
		// Репозиторий перепроверяет и source_url, и poster_url, но не
		// различает их в ошибке: сообщение не должно врать про поле.
		if errors.Is(err, metadata.ErrSourceURLTooLong) {
			return response.Error(c, fiber.StatusBadRequest, "Invalid metadata URL: too long (max 2048 characters)")
		}
		if errors.Is(err, metadata.ErrSourceURLInvalid) {
			return response.Error(c, fiber.StatusBadRequest, "Invalid metadata URL: must be an http(s) URL")
		}
		return repoError(c, err, "Media not found", "Failed to update metadata")
	}

	return c.JSON(media)
}
