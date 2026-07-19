package handlers

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// UploadHandler handles file uploads.
type UploadHandler struct {
	libraryRepo repository.LibraryRepository
	mediaRepo   repository.MediaRepository
	scanner     services.ScannerInterface
	config      UploadConfig
}

// UploadConfig holds upload-specific configuration.
type UploadConfig struct {
	AllowedExtensions []string
	MaxFileSize       int64
}

// NewUploadHandler creates a new UploadHandler.
func NewUploadHandler(
	libraryRepo repository.LibraryRepository,
	mediaRepo repository.MediaRepository,
	scanner services.ScannerInterface,
	config UploadConfig,
) *UploadHandler {
	return &UploadHandler{
		libraryRepo: libraryRepo,
		mediaRepo:   mediaRepo,
		scanner:     scanner,
		config:      config,
	}
}

// Upload handles multipart file upload.
func (h *UploadHandler) Upload(c *fiber.Ctx) error {
	// Parse library_id from form.
	libraryIDStr := c.FormValue("library_id")
	if libraryIDStr == "" {
		return response.Error(c, fiber.StatusBadRequest, "library_id is required")
	}

	libID, err := strconv.Atoi(libraryIDStr)
	if err != nil || libID <= 0 {
		return response.Error(c, fiber.StatusBadRequest, "library_id must be a positive number")
	}

	ctx := c.UserContext()
	library, err := h.libraryRepo.FindByID(ctx, uint(libID))
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "Library not found")
	}

	// Get uploaded file.
	fileHeader, err := c.FormFile("file")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "File is required")
	}

	// Check file size.
	if h.config.MaxFileSize > 0 && fileHeader.Size > h.config.MaxFileSize {
		return response.Error(c, fiber.StatusBadRequest, "File too large")
	}

	// Check extension.
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !h.isAllowedExtension(ext) {
		return response.Error(c, fiber.StatusBadRequest, "File type not allowed: "+ext)
	}

	// Ensure library directory exists.
	if err := os.MkdirAll(library.Path, 0755); err != nil {
		log.Printf("upload: mkdir %s: %v", library.Path, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create library directory")
	}

	// Save file to library path.
	dstPath := filepath.Join(library.Path, fileHeader.Filename)

	// Check if file already exists.
	if _, err := os.Stat(dstPath); err == nil {
		return response.Error(c, fiber.StatusConflict, "File already exists")
	}

	if err := c.SaveFile(fileHeader, dstPath); err != nil {
		log.Printf("upload: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save file")
	}

	// Create media record using scanner logic (hash, metadata, thumbnail).
	media, err := h.createMediaFromUpload(ctx, dstPath, fileHeader.Filename, library)
	if err != nil {
		log.Printf("upload: create media: %v", err)
		// File was saved but media creation failed — still return success with warning.
		return c.Status(fiber.StatusCreated).JSON(fiber.Map{
			"message": "File uploaded but media processing failed",
			"file":    fileHeader.Filename,
		})
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

// createMediaFromUpload creates a media record from an uploaded file.
func (h *UploadHandler) createMediaFromUpload(ctx context.Context, filePath, filename string, library *models.MediaLibrary) (*models.Media, error) {
	// Compute hashes.
	hash, err := services.HashFile(filePath)
	if err != nil {
		return nil, err
	}

	// Check for duplicates.
	existing, err := h.mediaRepo.FindByHash(ctx, hash)
	if err == nil && existing != nil {
		return nil, fiber.NewError(fiber.StatusConflict, "Duplicate file")
	}

	// Parse filename.
	title, year := metadata.ParseFilenameUpload(filename)

	// Determine media type.
	mediaType := services.DetermineMediaType(filePath, library.Type)

	info, _ := os.Stat(filePath)
	fileSize := int64(0)
	if info != nil {
		fileSize = info.Size()
	}

	media := &models.Media{
		Title:    title,
		Year:     year,
		Type:     mediaType,
		FilePath: filePath,
		FileSize: fileSize,
		FileHash: hash,
	}

	if err := h.mediaRepo.Create(ctx, media); err != nil {
		return nil, err
	}

	// Extract metadata from file.
 extractor := services.NewMetadataExtractor()
	if fileMeta := extractor.ExtractFromFile(filePath); fileMeta != nil {
		if fileMeta.Duration > 0 {
			media.Duration = fileMeta.Duration
		}
		if fileMeta.Artist != "" {
			media.Artist = fileMeta.Artist
		}
		if fileMeta.Album != "" {
			media.Album = fileMeta.Album
		}
		if fileMeta.Genre != "" {
			media.Genre = fileMeta.Genre
		}
		if fileMeta.Title != "" {
			media.Title = fileMeta.Title
		}
		h.mediaRepo.Update(ctx, media)
	}

	// Generate thumbnail.
 thumbSvc := services.NewThumbnailService("")
	if thumbPath := thumbSvc.Generate(media.ID, filePath); thumbPath != "" {
		media.ThumbnailURL = thumbPath
		h.mediaRepo.Update(ctx, media)
	}

	return media, nil
}

func (h *UploadHandler) isAllowedExtension(ext string) bool {
	for _, e := range h.config.AllowedExtensions {
		if ext == e {
			return true
		}
	}
	return false
}
