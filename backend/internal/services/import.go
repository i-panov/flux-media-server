package services

import (
	"context"
	"errors"
	"log"
	"sync"
	"time"

	"flux/internal/models"
	"flux/internal/repository"
)

// ImportSelection — выбранная пользователем серия.
type ImportSelection struct {
	Season  int
	Episode int
}

type ImportRequest struct {
	URL      string
	Scope    string
	Title    string
	SeriesID string
	Quality  string
	Format   string
	Episodes []ImportSelection
}

// ImportService переносит сезон/сериал из media-loader в каталог Flux.
// media-loader скачивает коллекцию целиком; Flux импортирует только
// выбранные серии, остальные остаются в кэше сервиса.
type ImportService struct {
	loader  *MediaLoader
	works   *repository.WorkStore
	imports *repository.ImportStore

	mu      sync.Mutex
	running map[uint]context.CancelFunc
}

func NewImportService(loader *MediaLoader, works *repository.WorkStore, imports *repository.ImportStore) *ImportService {
	return &ImportService{
		loader: loader, works: works, imports: imports,
		running: make(map[uint]context.CancelFunc),
	}
}

func (s *ImportService) Start(req ImportRequest) (*models.ImportJob, error) {
	episodes := make([]models.ImportEpisode, 0, len(req.Episodes))
	for _, selection := range req.Episodes {
		episodes = append(episodes, models.ImportEpisode{
			Season: selection.Season, Episode: selection.Episode,
			Status: models.ImportEpisodeQueued,
		})
	}
	job := &models.ImportJob{
		SourceURL: req.URL, Scope: req.Scope, Title: req.Title,
		SeriesID: req.SeriesID, Quality: req.Quality, Format: req.Format,
		Status: models.ImportQueued, Stage: "queued",
		EpisodesTotal: len(episodes),
	}
	if err := s.imports.Create(context.Background(), job, episodes); err != nil {
		return nil, err
	}
	// Верхний предел: зависший media-loader не должен держать задачу вечно.
	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Hour)
	s.mu.Lock()
	s.running[job.ID] = cancel
	s.mu.Unlock()
	go s.run(ctx, job, req, episodes)
	return job, nil
}

// RecoverStale помечает незавершённые задания ошибкой после рестарта:
// их рабочие горутины потеряны, и UI иначе опрашивает их бесконечно.
func (s *ImportService) RecoverStale(ctx context.Context) error {
	jobs, err := s.imports.List(ctx)
	if err != nil {
		return err
	}
	for _, job := range jobs {
		if job.Status == models.ImportQueued || job.Status == models.ImportDownloading ||
			job.Status == models.ImportImporting {
			if err := s.imports.Update(ctx, job.ID, map[string]any{
				"status": models.ImportError,
				"error":  "прервано перезапуском сервера",
			}); err != nil {
				return err
			}
			if _, episodes, err := s.imports.Get(ctx, job.ID); err == nil {
				for _, episode := range episodes {
					if episode.Status == models.ImportEpisodeQueued {
						_ = s.imports.UpdateEpisode(ctx, episode.ID, map[string]any{
							"status": models.ImportEpisodeError,
							"error":  "прервано перезапуском сервера",
						})
					}
				}
			}
		}
	}
	return nil
}

func (s *ImportService) Cancel(id uint) bool {
	s.mu.Lock()
	cancel, ok := s.running[id]
	s.mu.Unlock()
	if !ok {
		return false
	}
	cancel()
	_ = s.imports.Update(context.Background(), id, map[string]any{
		"status": models.ImportError, "error": "cancelled",
	})
	return true
}

func (s *ImportService) run(ctx context.Context, job *models.ImportJob, req ImportRequest, episodes []models.ImportEpisode) {
	defer func() {
		s.mu.Lock()
		delete(s.running, job.ID)
		s.mu.Unlock()
	}()
	_ = s.imports.Update(ctx, job.ID, map[string]any{
		"status": models.ImportDownloading, "stage": "downloading",
	})

	byKey := make(map[[2]int]*models.ImportEpisode, len(episodes))
	for i := range episodes {
		byKey[[2]int{episodes[i].Season, episodes[i].Episode}] = &episodes[i]
	}

	done, failed := 0, 0
	workID := job.WorkID
	seasons := map[int]uint{}

	attach := func(item CollectionEpisode) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		episode, ok := byKey[[2]int{item.Season, item.Episode}]
		if !ok {
			// Серия не выбрана: файл остался в кэше media-loader.
			return nil
		}
		if item.DownloadURL == "" {
			failed++
			message := item.Error
			if message == "" {
				message = "media loader did not produce this episode"
			}
			_ = s.imports.UpdateEpisode(ctx, episode.ID, map[string]any{
				"status": models.ImportEpisodeError, "error": message,
			})
			_ = s.imports.Update(ctx, job.ID, map[string]any{
				"episodes_done": done, "episodes_error": failed,
			})
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		mediaID, err := s.loader.ImportDownload(ctx, item.DownloadURL, item.Filename, "video/mp4")
		if err != nil {
			failed++
			_ = s.imports.UpdateEpisode(ctx, episode.ID, map[string]any{
				"status": models.ImportEpisodeError, "error": err.Error(),
			})
			_ = s.imports.Update(ctx, job.ID, map[string]any{
				"episodes_done": done, "episodes_error": failed,
			})
			// Ошибка одной серии не должна останавливать импорт остальных.
			//nolint:nilerr // ошибка серии учтена в счётчиках, проход продолжается.
			return nil
		}
		if workID == 0 {
			created, err := s.ensureWork(ctx, job, req)
			if err != nil {
				return err
			}
			workID = created
			_ = s.imports.Update(ctx, job.ID, map[string]any{"work_id": workID})
		}
		seasonID, ok := seasons[item.Season]
		if !ok {
			id, err := s.ensureSeason(ctx, workID, item.Season)
			if err != nil {
				return err
			}
			seasonID = id
			seasons[item.Season] = id
		}
		number := item.Episode
		if _, err := s.works.AddEpisode(ctx, seasonID, mediaID, &number); err != nil {
			_ = s.imports.UpdateEpisode(ctx, episode.ID, map[string]any{
				"status": models.ImportEpisodeError, "error": err.Error(), "media_id": mediaID,
			})
			failed++
		} else {
			done++
			title := item.Title
			_ = s.imports.UpdateEpisode(ctx, episode.ID, map[string]any{
				"status": models.ImportEpisodeDone, "media_id": mediaID, "title": title,
			})
		}
		_ = s.imports.Update(ctx, job.ID, map[string]any{
			"episodes_done": done, "episodes_error": failed,
		})
		return nil
	}

	err := s.loader.RunCollection(ctx, MediaLoaderRequest{
		URL: req.URL, Format: req.Format, Quality: req.Quality,
	}, req.Scope, func(stage string, percent float64) {
		_ = s.imports.Update(ctx, job.ID, map[string]any{
			"status": models.ImportDownloading, "stage": stage,
		})
	}, attach)
	if err != nil {
		log.Printf("import %d: %v", job.ID, err)
		_ = s.imports.Update(context.Background(), job.ID, map[string]any{
			"status": models.ImportError, "error": err.Error(),
			"episodes_done": done, "episodes_error": failed,
		})
		return
	}
	status := models.ImportDone
	if failed > 0 && done > 0 {
		status = models.ImportPartial
	} else if done == 0 {
		status = models.ImportError
	}
	_ = s.imports.Update(context.Background(), job.ID, map[string]any{
		"status": status, "stage": "done",
		"episodes_done": done, "episodes_error": failed,
	})
}

func (s *ImportService) ensureWork(ctx context.Context, job *models.ImportJob, req ImportRequest) (uint, error) {
	title := req.Title
	if title == "" {
		title = job.Title
	}
	if title == "" {
		title = "Импорт " + req.SeriesID
	}
	// Повторный импорт следующего сезона должен дополнять существующий
	// сериал, а не создавать второй с тем же названием.
	if existing, found, err := s.works.FindSeriesByTitle(ctx, title); err != nil {
		if !errors.Is(err, repository.ErrWorkTitleRequired) {
			return 0, err
		}
	} else if found && existing != nil {
		return existing.ID, nil
	}
	work := models.Work{Kind: models.WorkKindSeries, Title: title}
	if err := s.works.Create(ctx, &work); err != nil {
		return 0, err
	}
	return work.ID, nil
}

func (s *ImportService) ensureSeason(ctx context.Context, workID uint, number int) (uint, error) {
	work, err := s.works.Get(ctx, workID)
	if err != nil {
		return 0, err
	}
	for _, season := range work.Seasons {
		if season.SeasonNumber == number {
			return season.ID, nil
		}
	}
	season, err := s.works.CreateSeason(ctx, workID, number, "")
	if err != nil {
		return 0, err
	}
	return season.ID, nil
}

var _ = time.Second
