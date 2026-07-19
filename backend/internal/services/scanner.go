package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"flux/internal/config"
	"flux/internal/metadata"
	"flux/internal/models"
	"flux/internal/repository"
)

const quickHashChunk = 1024 * 1024 // 1MB head/tail for quick hash

type ScannerService struct {
	libraryRepo repository.LibraryRepository
	mediaRepo   repository.MediaRepository
	config      *config.Config

	mu       sync.RWMutex
	statuses map[uint]*ScanStatus
}

func NewScannerService(
	libraryRepo repository.LibraryRepository,
	mediaRepo repository.MediaRepository,
	config *config.Config,
) *ScannerService {
	return &ScannerService{
		libraryRepo: libraryRepo,
		mediaRepo:   mediaRepo,
		config:      config,
		statuses:    make(map[uint]*ScanStatus),
	}
}

func (s *ScannerService) ScanAll(ctx context.Context) error {
	libraries, err := s.libraryRepo.FindAll(ctx)
	if err != nil {
		return err
	}

	for _, lib := range libraries {
		if lib.Enabled {
			if err := s.ScanLibrary(ctx, lib.ID); err != nil {
				log.Printf("Error scanning library %s: %v", lib.Name, err)
			}
		}
	}

	return nil
}

func (s *ScannerService) GetScanStatus(libraryID uint) *ScanStatus {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if st, ok := s.statuses[libraryID]; ok {
		cp := *st
		return &cp
	}
	return &ScanStatus{LibraryID: libraryID, Running: false}
}

func (s *ScannerService) ScanLibrary(ctx context.Context, libraryID uint) error {
	library, err := s.libraryRepo.FindByID(ctx, libraryID)
	if err != nil {
		return err
	}

	s.mu.Lock()
	s.statuses[libraryID] = &ScanStatus{
		LibraryID: libraryID,
		Running:   true,
		StartedAt: time.Now().UTC().Format(time.RFC3339),
	}
	s.mu.Unlock()

	scanErr := s.scanLibraryWalk(ctx, library)

	s.mu.Lock()
	st := s.statuses[libraryID]
	st.Running = false
	if scanErr != nil {
		st.Error = scanErr.Error()
	} else {
		st.Error = ""
	}
	s.mu.Unlock()

	return scanErr
}

func (s *ScannerService) scanLibraryWalk(ctx context.Context, library *models.MediaLibrary) error {
	return filepath.Walk(library.Path, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			log.Printf("Walk error for %s: %v", path, err)
			return nil
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
		existing, err := s.mediaRepo.FindByPath(ctx, path)
		if err == nil && existing != nil {
			// File exists — check if it changed using quick hash
			qh, err := quickHashFile(path)
			if err != nil {
				log.Printf("Error quick-hashing file %s: %v", path, err)
				return nil
			}

			if existing.QuickHash == qh {
				return nil // unchanged
			}

			// File changed — recompute full hash and update
			fullHash, err := hashFile(path)
			if err != nil {
				log.Printf("Error hashing changed file %s: %v", path, err)
				return nil
			}

			title, year := metadata.ParseFilename(filepath.Base(path))
			existing.Title = title
			existing.Year = year
			existing.FileSize = info.Size()
			existing.FileHash = fullHash
			existing.QuickHash = qh

			if err := s.mediaRepo.Update(ctx, existing); err != nil {
				log.Printf("Error updating changed file %s: %v", path, err)
			} else {
				log.Printf("Updated changed file: %s", path)
			}
			return nil
		}

		// New file — compute both hashes
		qh, err := quickHashFile(path)
		if err != nil {
			log.Printf("Error quick-hashing file %s: %v", path, err)
			return nil
		}

		hash, err := hashFile(path)
		if err != nil {
			log.Printf("Error hashing file %s: %v", path, err)
			return nil
		}

		// Check if file with same hash already exists
		duplicate, err := s.mediaRepo.FindByHash(ctx, hash)
		if err == nil && duplicate != nil {
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

		media := &models.Media{
			Title:    title,
			Year:     year,
			Type:     mediaType,
			FilePath: path,
			FileSize: info.Size(),
			FileHash: hash,
			QuickHash: qh,
		}

		if err := s.mediaRepo.Create(ctx, media); err != nil {
			log.Printf("Error creating media record for %s: %v", path, err)
		}

		return nil
	})
}

// hashFile computes full SHA-256 of a file.
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

// quickHashFile computes a fast hash from the first and last 1MB of a file
// plus the file size. This is sufficient for detecting file changes without
// reading the entire file.
func quickHashFile(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return "", err
	}

	h := sha256.New()

	// Hash file size
	sizeBuf := make([]byte, 8)
	size := stat.Size()
	for i := 7; i >= 0; i-- {
		sizeBuf[i] = byte(size)
		size >>= 8
	}
	h.Write(sizeBuf)

	// Hash first chunk
	head := make([]byte, quickHashChunk)
	n, _ := io.ReadFull(f, head)
	if n > 0 {
		h.Write(head[:n])
	}

	// Hash last chunk (if file is larger than 2x chunk)
	fileSize := stat.Size()
	if fileSize > int64(quickHashChunk*2) {
		f.Seek(-int64(quickHashChunk), io.SeekEnd)
		tail := make([]byte, quickHashChunk)
		n, _ := io.ReadFull(f, tail)
		if n > 0 {
			h.Write(tail[:n])
		}
	}

	return hex.EncodeToString(h.Sum(nil)), nil
}
