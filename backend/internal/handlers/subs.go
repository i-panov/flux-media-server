package handlers

import (
	"fmt"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// SubsHandler обслуживает WebVTT-сайдкары текстовых дорожек.
type SubsHandler struct {
	mediaRepo repository.MediaRepository
	subRepo   repository.SubtitleRepository
	mediaCfg  config.MediaConfig
}

func NewSubsHandler(mediaRepo repository.MediaRepository, subRepo repository.SubtitleRepository, mediaCfg config.MediaConfig) *SubsHandler {
	return &SubsHandler{mediaRepo: mediaRepo, subRepo: subRepo, mediaCfg: mediaCfg}
}

type subListItem struct {
	Lang string `json:"lang"`
	URL  string `json:"url"`
}

// ListSubs возвращает текстовые дорожки медиа со ссылками на файлы.
func (h *SubsHandler) ListSubs(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}

	ctx := c.UserContext()
	if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	subs, err := h.subRepo.ListByMedia(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch subtitles")
	}

	items := make([]subListItem, 0, len(subs))
	for _, sub := range subs {
		items = append(items, subListItem{
			Lang: sub.Lang,
			URL:  fmt.Sprintf("/api/media/%d/subs/%s", mediaID, sub.Lang),
		})
	}
	return c.JSON(items)
}

// ServeSub отдаёт WebVTT-файл дорожки. Путь берётся только из БД;
// дополнительно проверяется принадлежность библиотеке — на случай
// подменённой строки (оборона в глубину, стоит дёшево).
func (h *SubsHandler) ServeSub(c *fiber.Ctx) error {
	mediaID, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid media ID")
	}
	lang := c.Params("lang")
	// То же правило, что sanitizeLang при генерации имён (единый
	// services.ValidSubtitleLang): URL из ListSubs всегда проходят.
	if !services.ValidSubtitleLang(lang) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid subtitle language")
	}

	ctx := c.UserContext()
	if _, err := h.mediaRepo.FindByID(ctx, mediaID); err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch media")
	}

	subs, err := h.subRepo.ListByMedia(ctx, mediaID)
	if err != nil {
		return repoError(c, err, "Media not found", "Failed to fetch subtitles")
	}
	for _, sub := range subs {
		if sub.Lang == lang {
			if !services.IsSubPath(h.mediaCfg.VideoPath, sub.Path) &&
				!services.IsSubPath(h.mediaCfg.AudioPath, sub.Path) {
				return response.Error(c, fiber.StatusNotFound, "Subtitle not available")
			}
			c.Set("Content-Type", "text/vtt; charset=utf-8")
			return c.SendFile(sub.Path)
		}
	}
	return response.Error(c, fiber.StatusNotFound, "Subtitle not available")
}
