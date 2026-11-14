package handlers

import (
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/response"
	"flux/internal/services"
)

// DownloadHandler ставит серверную загрузку через media-loader и отдаёт
// статус импорта в медиатеку. Доступ — только админ: это сетевой доступ
// и запуск yt-dlp/ffmpeg от имени сервера.
type DownloadHandler struct {
	loader *services.MediaLoader
}

func NewDownloadHandler(loader *services.MediaLoader) *DownloadHandler {
	return &DownloadHandler{loader: loader}
}

type downloadRequest struct {
	URL       string `json:"url"`
	AudioOnly bool   `json:"audio_only"`
	Format    string `json:"format"`
	Quality   string `json:"quality"`
}

func (h *DownloadHandler) Create(c *fiber.Ctx) error {
	if !h.loader.Enabled() {
		return response.Error(c, fiber.StatusServiceUnavailable, "Media loader is not configured")
	}
	var req downloadRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	req.URL = strings.TrimSpace(req.URL)
	if req.URL == "" {
		return response.Error(c, fiber.StatusBadRequest, "url is required")
	}
	if req.AudioOnly {
		req.Format = strings.ToLower(strings.TrimSpace(req.Format))
		req.Quality = ""
	} else {
		req.Format = strings.ToLower(strings.TrimSpace(req.Format))
		req.Quality = strings.ToLower(strings.TrimSpace(req.Quality))
		if req.Quality == "max" {
			// media-loader понимает отсутствие quality как «максимум»;
			// строку "max" его валидатор отвергает.
			req.Quality = ""
		}
	}
	job, err := h.loader.Submit(services.MediaLoaderRequest{
		URL: req.URL, AudioOnly: req.AudioOnly,
		Format: req.Format, Quality: req.Quality,
	})
	if err != nil {
		if errors.Is(err, services.ErrMediaLoaderDisabled) {
			return response.Error(c, fiber.StatusServiceUnavailable, "Media loader is not configured")
		}
		return response.Error(c, fiber.StatusBadRequest, err.Error())
	}
	return c.Status(fiber.StatusAccepted).JSON(job)
}

func (h *DownloadHandler) Status(c *fiber.Ctx) error {
	job, ok := h.loader.Get(c.Params("id"))
	if !ok {
		return response.Error(c, fiber.StatusNotFound, "Download job not found")
	}
	return c.JSON(job)
}

func (h *DownloadHandler) Cancel(c *fiber.Ctx) error {
	if err := h.loader.Cancel(c.Params("id")); err != nil {
		if errors.Is(err, services.ErrMediaLoaderJobGone) {
			return response.Error(c, fiber.StatusNotFound, "Download job not found")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to cancel download")
	}
	return c.SendStatus(fiber.StatusNoContent)
}
