package handlers

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

type LyricsHandler struct {
	lyricsRepo repository.LyricsRepository
	mediaRepo  repository.MediaRepository
}

func NewLyricsHandler(lyricsRepo repository.LyricsRepository, mediaRepo repository.MediaRepository) *LyricsHandler {
	return &LyricsHandler{lyricsRepo: lyricsRepo, mediaRepo: mediaRepo}
}

// GetLyrics returns lyrics for a media item.
func (h *LyricsHandler) GetLyrics(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	lyrics, err := h.lyricsRepo.FindByMediaID(ctx, uint(mediaID))
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Lyrics not found")
		}
		log.Printf("GetLyrics: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch lyrics")
	}

	return c.JSON(lyrics)
}

type UpsertLyricsRequest struct {
	LyricsText  string `json:"lyrics_text"`
	Translation string `json:"translation"`
	SyncData    string `json:"sync_data"`
	Source      string `json:"source"`
}

// UpsertLyrics creates or updates lyrics for a media item.
// When updating, only non-empty fields in the request are applied — this
// prevents the client from accidentally erasing translation/sync_data when
// it only wants to update the lyrics text.
func (h *LyricsHandler) UpsertLyrics(c *fiber.Ctx) error {
	mediaID, err := c.ParamsInt("id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	var req UpsertLyricsRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	ctx := c.UserContext()

	// Проверяем существование медиа до создания/обновления текста.
	if _, err := h.mediaRepo.FindByID(ctx, uint(mediaID)); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	lyrics := &models.Lyrics{
		MediaID:     uint(mediaID),
		LyricsText:  req.LyricsText,
		Translation: req.Translation,
		SyncData:    req.SyncData,
		Source:      req.Source,
	}

	// If a record already exists, preserve fields that the client did not
	// send (empty string in the request). This prevents PUT from erasing
	// translation/sync_data when only lyrics_text is being saved.
	existing, findErr := h.lyricsRepo.FindByMediaID(ctx, uint(mediaID))
	if findErr == nil && existing != nil {
		if req.LyricsText == "" {
			lyrics.LyricsText = existing.LyricsText
		}
		if req.Translation == "" {
			lyrics.Translation = existing.Translation
		}
		if req.SyncData == "" {
			lyrics.SyncData = existing.SyncData
		}
		if req.Source == "" {
			lyrics.Source = existing.Source
		}
		// Preserve the ID so OnConflict updates the existing row.
		lyrics.ID = existing.ID
	}

	if err := h.lyricsRepo.Upsert(ctx, lyrics); err != nil {
		log.Printf("UpsertLyrics: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save lyrics")
	}

	return c.JSON(lyrics)
}
