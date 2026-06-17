package services

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	"flux/internal/config"
	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

type ScannerService struct {
	libraryRepo *repository.LibraryRepository
	mediaRepo   *repository.MediaRepository
	config      *config.Config
}

func NewScannerService(
	libraryRepo *repository.LibraryRepository,
	mediaRepo *repository.MediaRepository,
	config *config.Config,
) *ScannerService {
	return &ScannerService{
		libraryRepo: libraryRepo,
		mediaRepo:   mediaRepo,
		config:      config,
	}
}

func (s *ScannerService) ScanAll() error {
	libraries, err := s.libraryRepo.FindAll()
	if err != nil {
		return err
	}

	for _, lib := range libraries {
		if lib.Enabled {
			if err := s.ScanLibrary(&lib); err != nil {
				log.Printf("Error scanning library %s: %v", lib.Name, err)
			}
		}
	}

	return nil
}

func hashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}

func (s *ScannerService) ScanLibrary(library *models.MediaLibrary) error {
	return filepath.Walk(library.Path, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		// Check file extension
		ext := strings.ToLower(filepath.Ext(path))
		allowed := false
		for _, e := range s.config.Media.AllowedExtensions {
			if ext == e {
				allowed = true
				break
			}
		}

		if !allowed {
			return nil
		}

		// Check if file already exists in database by path
		existing, _ := s.mediaRepo.FindByPath(path)
		if existing != nil {
			return nil
		}

		// Compute file hash
		hash, err := hashFile(path)
		if err != nil {
			log.Printf("Error hashing file %s: %v", path, err)
			return nil
		}

		// Check if file with same hash already exists
		duplicate, _ := s.mediaRepo.FindByHash(hash)
		if duplicate != nil {
			log.Printf("Skipping duplicate: %s (same hash as %s)", path, duplicate.FilePath)
			return nil
		}

		// Parse filename for metadata
		title, year := metadata.ParseFilename(filepath.Base(path))

		// Determine media type
		mediaType := "movie"
		if library.Type == "tv" {
			mediaType = "episode"
		}

		// Get file info
		fileInfo, err := os.Stat(path)
		if err != nil {
			return err
		}

		// Create media record
		media := &models.Media{
			Title:    title,
			Year:     year,
			Type:     mediaType,
			FilePath: path,
			FileSize: fileInfo.Size(),
			FileHash: hash,
		}

		if err := s.mediaRepo.Create(media); err != nil {
			log.Printf("Error creating media record for %s: %v", path, err)
		}

		return nil
	})
}