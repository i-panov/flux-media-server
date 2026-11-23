package services

import (
	"context"
	"errors"
	"log"
	"strconv"

	"gorm.io/gorm"

	"flux/internal/models"
	"flux/internal/repository"
)

// ThumbnailQueueService — постоянная очередь превью и обложек.
// Задания лежат в БД, поэтому рестарт не теряет очередь: при старте
// приложения незавершённые задачи продолжаются тем же воркером.
type ThumbnailQueueService struct {
	tasks *repository.ThumbnailStore
	media repository.MediaRepository
	thumb *ThumbnailService
}

func NewThumbnailQueueService(tasks *repository.ThumbnailStore, media repository.MediaRepository, thumb *ThumbnailService) *ThumbnailQueueService {
	return &ThumbnailQueueService{tasks: tasks, media: media, thumb: thumb}
}

// EnqueueMissing ставит в очередь всё, чему не хватает превью или обложки.
func (s *ThumbnailQueueService) EnqueueMissing(ctx context.Context, kind string) error {
	if err := s.tasks.ResetFinished(ctx, kind); err != nil {
		return err
	}
	if kind == models.ThumbnailKindCover {
		lastID := uint(0)
		for {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			rows, err := s.media.FindAudioCoverCandidates(ctx, lastID, thumbnailBackfillBatch)
			if err != nil {
				return err
			}
			if len(rows) == 0 {
				return nil
			}
			for _, media := range rows {
				lastID = media.ID
				if err := s.tasks.Enqueue(ctx, media.ID, kind); err != nil {
					return err
				}
			}
			if len(rows) < thumbnailBackfillBatch {
				return nil
			}
		}
	}
	lastID := uint(0)
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		rows, err := s.media.FindThumbnailCandidates(ctx, lastID, thumbnailBackfillBatch)
		if err != nil {
			return err
		}
		if len(rows) == 0 {
			return nil
		}
		for _, media := range rows {
			lastID = media.ID
			// Файл есть и URL на месте — задача не нужна. Если URL пуст,
			// задача восстановит ссылку, даже когда файл уже существует.
			if s.thumb != nil && s.thumb.Exists(media.ID) && media.ThumbnailURL != "" {
				continue
			}
			if err := s.tasks.Enqueue(ctx, media.ID, kind); err != nil {
				return err
			}
		}
		if len(rows) < thumbnailBackfillBatch {
			return nil
		}
	}
}

// RecoverStale возвращает в очередь задачи, оставшиеся processing после
// падения процесса. Вызывается только на старте: админский клик не должен
// «угонять» задачу у работающего воркера.
func (s *ThumbnailQueueService) RecoverStale(ctx context.Context) {
	for _, kind := range []string{models.ThumbnailKindThumb, models.ThumbnailKindCover} {
		if requeued, err := s.tasks.RequeueProcessing(ctx, kind); err != nil {
			log.Printf("thumbnail queue: requeue %s: %v", kind, err)
		} else if requeued > 0 {
			log.Printf("thumbnail queue: requeued %d stale %s tasks", requeued, kind)
		}
	}
}

// Run обрабатывает очередь до конца и возвращает счётчики.
func (s *ThumbnailQueueService) Run(ctx context.Context, kind string) (int, int) {
	generated, failed := 0, 0
	for {
		if ctx.Err() != nil {
			return generated, failed
		}
		task, err := s.tasks.NextQueued(ctx, kind)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return generated, failed
			}
			log.Printf("thumbnail queue: claim %s: %v", kind, err)
			return generated, failed
		}
		media, err := s.media.FindByID(ctx, task.MediaID)
		if err != nil {
			failed++
			if err := s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskError, "media not found"); err != nil {
				log.Printf("thumbnail queue: finish %d: %v", task.ID, err)
			}
			continue
		}
		ok := false
		if kind == models.ThumbnailKindThumb {
			ok = s.processThumbnail(ctx, media)
		} else {
			ok = s.processCover(ctx, media)
		}
		if ok {
			generated++
			if err := s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskDone, ""); err != nil {
				log.Printf("thumbnail queue: finish %d: %v", task.ID, err)
			}
		} else {
			failed++
			if err := s.tasks.Finish(ctx, task.ID, models.ThumbnailTaskError, "generation failed"); err != nil {
				log.Printf("thumbnail queue: finish %d: %v", task.ID, err)
			}
		}
	}
}

func (s *ThumbnailQueueService) processThumbnail(ctx context.Context, media *models.Media) bool {
	if s.thumb.Exists(media.ID) {
		// Файл есть, но URL потерян — восстанавливаем ссылку.
		if media.ThumbnailURL == "" {
			url := "/api/media/" + strconv.FormatUint(uint64(media.ID), 10) + "/thumb"
			if err := s.media.UpdateThumbnailURL(ctx, media.ID, url); err != nil {
				log.Printf("thumbnail queue: restore url %d: %v", media.ID, err)
				return false
			}
		}
		return true
	}
	url := s.thumb.GenerateWithContext(ctx, media.ID, media.FilePath)
	if url == "" {
		log.Printf("thumbnail queue: generation failed for %d", media.ID)
		return false
	}
	if err := s.media.UpdateThumbnailURL(ctx, media.ID, url); err != nil {
		log.Printf("thumbnail queue: save url for %d: %v", media.ID, err)
		return false
	}
	return true
}

func (s *ThumbnailQueueService) processCover(ctx context.Context, media *models.Media) bool {
	if media.CoverURL != "" {
		return true
	}
	if s.thumb.ExtractCoverContext(ctx, media.ID, media.FilePath) == "" {
		_ = s.media.SetCoverAttempted(ctx, media.ID, true)
		return false
	}
	if err := s.media.UpdateCoverURL(ctx, media.ID, "/api/media/"+strconv.FormatUint(uint64(media.ID), 10)+"/cover"); err != nil {
		return false
	}
	_ = s.media.SetCoverAttempted(ctx, media.ID, true)
	return true
}
