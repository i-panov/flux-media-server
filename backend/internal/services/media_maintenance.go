package services

import (
	"context"
	"fmt"
	"sync"
	"time"

	"flux/internal/models"
	"flux/internal/repository"
)

type MaintenanceState struct {
	Running    bool      `json:"running"`
	Kind       string    `json:"kind,omitempty"`
	Generated  int       `json:"generated"`
	Failed     int       `json:"failed"`
	LastError  string    `json:"last_error,omitempty"`
	StartedAt  time.Time `json:"started_at,omitempty"`
	FinishedAt time.Time `json:"finished_at,omitempty"`
}

// MediaMaintenanceService запускает тяжёлые фоновые проходы по медиа из
// админки: превью и встроенные обложки. Одновременно — только один проход.
type MediaMaintenanceService struct {
	mu     sync.Mutex
	state  MaintenanceState
	media  repository.MediaRepository
	thumbs *ThumbnailService
	queue  *ThumbnailQueueService
}

func NewMediaMaintenanceService(media repository.MediaRepository, thumbs *ThumbnailService, queue *ThumbnailQueueService) *MediaMaintenanceService {
	return &MediaMaintenanceService{media: media, thumbs: thumbs, queue: queue}
}

func (s *MediaMaintenanceService) Status() MaintenanceState {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.state
}

func (s *MediaMaintenanceService) start(kind string, run func(context.Context) (int, int)) bool {
	s.mu.Lock()
	if s.state.Running {
		s.mu.Unlock()
		return false
	}
	s.state = MaintenanceState{Running: true, Kind: kind, StartedAt: time.Now().UTC()}
	s.mu.Unlock()
	go func() {
		generated, failed := run(context.Background())
		s.mu.Lock()
		s.state.Running = false
		s.state.Generated = generated
		s.state.Failed = failed
		if failed > 0 {
			s.state.LastError = fmt.Sprintf("failed files: %d", failed)
		}
		s.state.FinishedAt = time.Now().UTC()
		s.mu.Unlock()
	}()
	return true
}

func (s *MediaMaintenanceService) StartThumbnails() bool {
	return s.start("thumbnails", func(ctx context.Context) (int, int) {
		if err := s.queue.EnqueueMissing(ctx, models.ThumbnailKindThumb); err != nil {
			return 0, 0
		}
		return s.queue.Run(ctx, models.ThumbnailKindThumb)
	})
}

func (s *MediaMaintenanceService) StartCovers() bool {
	return s.start("covers", func(ctx context.Context) (int, int) {
		if err := s.queue.EnqueueMissing(ctx, models.ThumbnailKindCover); err != nil {
			return 0, 0
		}
		return s.queue.Run(ctx, models.ThumbnailKindCover)
	})
}
