package handlers

import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
)

// maxArtistCoverSize — максимальный размер обложки артиста (10 МБ).
const maxArtistCoverSize = 10 << 20

// artistCoverExts — допустимые расширения обложки артиста.
var artistCoverExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true,
}

type ArtistHandler struct {
	artistRepo repository.ArtistRepository
	coverDir   string
}

func NewArtistHandler(
	artistRepo repository.ArtistRepository,
	coverDir string,
) *ArtistHandler {
	return &ArtistHandler{artistRepo: artistRepo, coverDir: coverDir}
}

// artistCoverFile возвращает путь к файлу обложки артиста (если есть).
func (h *ArtistHandler) artistCoverFile(id uint) (string, error) {
	pattern := filepath.Join(h.coverDir, fmt.Sprintf("artist_%d.*", id))
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return "", err
	}
	for _, m := range matches {
		ext := strings.ToLower(filepath.Ext(m))
		if artistCoverExts[ext] {
			return m, nil
		}
	}
	return "", nil
}

// artistHasCover — есть ли у артиста файл обложки на диске.
func (h *ArtistHandler) artistHasCover(id uint) (bool, error) {
	path, err := h.artistCoverFile(id)
	if err != nil || path == "" {
		return false, err
	}
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, nil
		}
		return false, err
	}
	return !info.IsDir(), nil
}

// List returns all artists ordered by name.
func (h *ArtistHandler) List(c *fiber.Ctx) error {
	ctx := c.UserContext()
	artists, err := h.artistRepo.FindAll(ctx)
	if err != nil {
		log.Printf("ArtistHandler.List: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to fetch artists")
	}
	if artists == nil {
		artists = []models.Artist{}
	}
	// Обложка артиста — файл на диске; признак считаем здесь, чтобы
	// клиент знал, грузить ли картинку.
	for i := range artists {
		has, err := h.artistHasCover(artists[i].ID)
		if err != nil {
			log.Printf("ArtistHandler.List cover stat: %v", err)
			continue
		}
		artists[i].HasCover = has
	}
	return c.JSON(fiber.Map{"items": artists})
}

// Update переименовывает артиста (имя меняется у всех его треков).
func (h *ArtistHandler) Update(c *fiber.Ctx) error {
	ctx := c.UserContext()
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid artist id")
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		return response.Error(c, fiber.StatusBadRequest, "Name is required")
	}

	artist, err := h.artistRepo.Update(ctx, id, req.Name)
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrArtistNameTaken):
			return response.Error(c, fiber.StatusConflict, "Artist name already exists")
		case errors.Is(err, gorm.ErrRecordNotFound):
			return response.Error(c, fiber.StatusNotFound, "Artist not found")
		default:
			log.Printf("ArtistHandler.Update: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to update artist")
		}
	}
	return c.JSON(artist)
}

// UploadCover сохраняет обложку артиста (jpg/jpeg/png/webp, до 10 МБ).
func (h *ArtistHandler) UploadCover(c *fiber.Ctx) error {
	ctx := c.UserContext()
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid artist id")
	}

	fileHeader, err := c.FormFile("cover")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Cover file is required")
	}
	if fileHeader.Size == 0 {
		return response.Error(c, fiber.StatusBadRequest, "Cover file is empty")
	}
	if fileHeader.Size > maxArtistCoverSize {
		return response.Error(c, fiber.StatusRequestEntityTooLarge, "Cover file too large")
	}

	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !artistCoverExts[ext] {
		return response.Error(c, fiber.StatusBadRequest, "Unsupported cover format")
	}

	if err := os.MkdirAll(h.coverDir, 0755); err != nil {
		log.Printf("ArtistHandler.UploadCover mkdir: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create cover directory")
	}

	dst := filepath.Join(h.coverDir, fmt.Sprintf("artist_%d%s", id, ext))
	// Сохраняем новую обложку; старые (других расширений) удаляем только
	// после успешного сохранения, чтобы при сбое осталась прежняя.
	if err := c.SaveFile(fileHeader, dst); err != nil {
		log.Printf("ArtistHandler.UploadCover save: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save cover")
	}
	// Обновляем updated_at: клиент кеширует обложку по этому значению
	// (?v=updated_at), иначе после замены файла картинка останется старой.
	if err := h.artistRepo.Touch(ctx, id); err != nil {
		log.Printf("ArtistHandler.UploadCover touch: %v", err)
	}
	pattern := filepath.Join(h.coverDir, fmt.Sprintf("artist_%d.*", id))
	if matches, err := filepath.Glob(pattern); err == nil {
		for _, m := range matches {
			if m != dst {
				_ = os.Remove(m)
			}
		}
	}

	return c.JSON(fiber.Map{"ok": true})
}

// mimeTypeByExtForCover — MIME-тип обложки по расширению.
func mimeTypeByExtForCover(ext string) string {
	switch ext {
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	default:
		return "image/jpeg"
	}
}

// GetCover отдаёт обложку артиста (404 — обложки нет).
func (h *ArtistHandler) GetCover(c *fiber.Ctx) error {
	id, err := parseIDParam(c, "id")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid artist id")
	}

	path, err := h.artistCoverFile(id)
	if err != nil || path == "" {
		return response.Error(c, fiber.StatusNotFound, "Cover not found")
	}

	ext := strings.ToLower(filepath.Ext(path))
	c.Set("Content-Type", mimeTypeByExtForCover(ext))
	return c.SendFile(path)
}
