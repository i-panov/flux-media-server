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
}

func NewLyricsHandler(lyricsRepo repository.LyricsRepository) *LyricsHandler {
	return &LyricsHandler{lyricsRepo: lyricsRepo}
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

	lyrics := &models.Lyrics{
		MediaID:     uint(mediaID),
		LyricsText:  req.LyricsText,
		Translation: req.Translation,
		SyncData:    req.SyncData,
		Source:      req.Source,
	}

	if err := h.lyricsRepo.Upsert(ctx, lyrics); err != nil {
		log.Printf("UpsertLyrics: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save lyrics")
	}

	return c.JSON(lyrics)
}
