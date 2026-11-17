package handlers

import (
	"errors"
	"strings"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type ImportHandler struct {
	loader  *services.MediaLoader
	imports *repository.ImportStore
	service *services.ImportService
}

func NewImportHandler(loader *services.MediaLoader, imports *repository.ImportStore, service *services.ImportService) *ImportHandler {
	return &ImportHandler{loader: loader, imports: imports, service: service}
}

func (h *ImportHandler) Probe(c *fiber.Ctx) error {
	var req struct {
		URL string `json:"url"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	req.URL = strings.TrimSpace(req.URL)
	if req.URL == "" {
		return response.Error(c, fiber.StatusBadRequest, "url is required")
	}
	result, err := h.loader.ProbeSeries(c.UserContext(), req.URL)
	if err != nil {
		if errors.Is(err, services.ErrMediaLoaderDisabled) {
			return response.Error(c, fiber.StatusServiceUnavailable, "media loader is not configured")
		}
		return response.Error(c, fiber.StatusBadGateway, err.Error())
	}
	return c.JSON(result)
}

type importRequest struct {
	URL      string `json:"url"`
	Scope    string `json:"scope"`
	Title    string `json:"title"`
	SeriesID string `json:"series_id"`
	Quality  string `json:"quality"`
	Format   string `json:"format"`
	Episodes []struct {
		Season  int `json:"season"`
		Episode int `json:"episode"`
	} `json:"episodes"`
}

func (h *ImportHandler) Start(c *fiber.Ctx) error {
	var req importRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if strings.TrimSpace(req.URL) == "" {
		return response.Error(c, fiber.StatusBadRequest, "url is required")
	}
	scope := req.Scope
	if scope == "" {
		scope = "season"
	}
	if scope != "season" && scope != "series" {
		return response.Error(c, fiber.StatusBadRequest, "scope must be season or series")
	}
	if len(req.Episodes) == 0 {
		return response.Error(c, fiber.StatusBadRequest, "episodes are required")
	}
	selections := make([]services.ImportSelection, 0, len(req.Episodes))
	for _, episode := range req.Episodes {
		if episode.Season <= 0 || episode.Episode <= 0 {
			return response.Error(c, fiber.StatusBadRequest, "invalid episode numbers")
		}
		selections = append(selections, services.ImportSelection{
			Season: episode.Season, Episode: episode.Episode,
		})
	}
	job, err := h.service.Start(services.ImportRequest{
		URL: req.URL, Scope: scope, Title: req.Title, SeriesID: req.SeriesID,
		Quality: req.Quality, Format: req.Format, Episodes: selections,
	})
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to start import")
	}
	return c.Status(fiber.StatusAccepted).JSON(job)
}

func (h *ImportHandler) List(c *fiber.Ctx) error {
	jobs, err := h.imports.List(c.UserContext())
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to load imports")
	}
	if jobs == nil {
		jobs = []models.ImportJob{}
	}
	return c.JSON(jobs)
}

func (h *ImportHandler) Get(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid import ID")
	}
	job, episodes, err := h.imports.Get(c.UserContext(), id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Import not found")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to load import")
	}
	return c.JSON(fiber.Map{"job": job, "episodes": episodes})
}

func (h *ImportHandler) Cancel(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid import ID")
	}
	if !h.service.Cancel(id) {
		return response.Error(c, fiber.StatusNotFound, "Import is not running")
	}
	return c.SendStatus(fiber.StatusNoContent)
}
