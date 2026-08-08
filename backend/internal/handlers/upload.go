package handlers

import (
	"context"
	"errors"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

// UploadHandler handles file uploads.
type UploadHandler struct {
	mediaRepo repository.MediaRepository
	scanner   services.ScannerInterface
	thumbSvc  *services.ThumbnailService
	extractor *services.MetadataExtractor
	config    UploadConfig
	mediaCfg  config.MediaConfig
}

// UploadConfig holds upload-specific configuration.
type UploadConfig struct {
	MaxFileSize int64
}

// NewUploadHandler creates a new UploadHandler.
func NewUploadHandler(
	mediaRepo repository.MediaRepository,
	scanner services.ScannerInterface,
	thumbSvc *services.ThumbnailService,
	mediaCfg config.MediaConfig,
	config UploadConfig,
) *UploadHandler {
	return &UploadHandler{
		mediaRepo: mediaRepo,
		scanner:   scanner,
		thumbSvc:  thumbSvc,
		extractor: services.NewMetadataExtractor(),
		mediaCfg:  mediaCfg,
		config:    config,
	}
}

// Upload handles multipart file upload.
func (h *UploadHandler) Upload(c *fiber.Ctx) error {
	ctx := c.UserContext()

	// Resolve destination path by media_type.
	mediaType := c.FormValue("media_type")
	if mediaType == "" {
		mediaType = "video"
	}
	destPath := h.mediaCfg.VideoPath
	if mediaType == "audio" {
		destPath = h.mediaCfg.AudioPath
	}
	if destPath == "" {
		return response.Error(c, fiber.StatusInternalServerError, "No path configured for media type: "+mediaType)
	}

	// Get uploaded file.
	fileHeader, err := c.FormFile("file")
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "File is required")
	}

	// Check file is not empty.
	if fileHeader.Size == 0 {
		return response.Error(c, fiber.StatusBadRequest, "File is empty")
	}

	// Check file size.
	if h.config.MaxFileSize > 0 && fileHeader.Size > h.config.MaxFileSize {
		return response.Error(c, fiber.StatusBadRequest, "File too large")
	}

	// Sanitize the filename to prevent path traversal attacks.
	filename, err := services.SanitizeFilename(fileHeader.Filename)
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid filename")
	}

	// Check extension.
	ext := strings.ToLower(filepath.Ext(filename))
	if !h.isAllowedExtension(ext) {
		return response.Error(c, fiber.StatusBadRequest, "File type not allowed: "+ext)
	}

	// Ensure destination directory exists.
	if err := os.MkdirAll(destPath, 0755); err != nil {
		log.Printf("upload: mkdir %s: %v", destPath, err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create directory")
	}

	// Save file to destination path.
	dstPath := filepath.Join(destPath, filename)
	if !services.IsSubPath(destPath, dstPath) {
		return response.Error(c, fiber.StatusBadRequest, "Invalid filename")
	}

	// Check if file already exists.
	if _, err := os.Stat(dstPath); err == nil {
		return response.Error(c, fiber.StatusConflict, "File already exists")
	}

	if err := c.SaveFile(fileHeader, dstPath); err != nil {
		log.Printf("upload: save file: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to save file")
	}

	// Create media record using scanner logic (hash, metadata, thumbnail).
	media, err := h.createMediaFromUpload(ctx, dstPath, filename)
	if err != nil {
		log.Printf("upload: create media: %v", err)
		// Remove the orphaned file so we don't leave untracked data on disk.
		if rmErr := os.Remove(dstPath); rmErr != nil {
			log.Printf("upload: remove orphaned file %s: %v", dstPath, rmErr)
		}
		var fiberErr *fiber.Error
		if errors.As(err, &fiberErr) {
			return response.Error(c, fiberErr.Code, fiberErr.Message)
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to process uploaded file")
	}

	return c.Status(fiber.StatusCreated).JSON(media)
}

// createMediaFromUpload creates a media record from an uploaded file.
func (h *UploadHandler) createMediaFromUpload(ctx context.Context, filePath, filename string) (*models.Media, error) {
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

	// Parse filename for metadata
	title, year := metadata.ParseFilenameUpload(filename)

	// Determine media type
	mediaType := services.DetermineMediaType(filePath)

	info, _ := os.Stat(filePath)
	fileSize := int64(0)
	if info != nil {
		fileSize = info.Size()
	}

	media := &models.Media{
		Title:    title,
		Filename: filename,
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
	if fileMeta := h.extractor.ExtractFromFile(filePath); fileMeta != nil {
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
		if err := h.mediaRepo.Update(ctx, media); err != nil {
			log.Printf("upload: update media metadata: %v", err)
		}
	}

	// Generate thumbnail.
	if thumbPath := h.thumbSvc.Generate(media.ID, filePath); thumbPath != "" {
		media.ThumbnailURL = thumbPath
		if err := h.mediaRepo.Update(ctx, media); err != nil {
			log.Printf("upload: update media thumbnail: %v", err)
		}
	}

	// Extract embedded cover art (if file has one).
	if coverPath := h.thumbSvc.ExtractCover(media.ID, filePath); coverPath != "" {
		media.CoverURL = coverPath
		if err := h.mediaRepo.Update(ctx, media); err != nil {
			log.Printf("upload: update media cover: %v", err)
		}
	}

	return media, nil
}

func (h *UploadHandler) isAllowedExtension(ext string) bool {
	return services.IsAllowedExtension(ext)
}
