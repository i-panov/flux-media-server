package repository

import (
	"context"
	"errors"

	"flux/internal/models"

	"gorm.io/gorm"
)

var (
	ErrInvalidWorkKind        = errors.New("invalid work kind")
	ErrWorkTitleRequired      = errors.New("work title is required")
	ErrSeasonNumberInvalid    = errors.New("season number must be >= 0")
	ErrLastSeason             = errors.New("series must keep at least one season")
	ErrNotSeries              = errors.New("work is not a series")
	ErrNotFilmSeries          = errors.New("work is not a film series")
	ErrMediaNotVideo          = errors.New("media is not a video")
	ErrEpisodeAlreadyInSeason = errors.New("episode already belongs to a season")
	ErrEpisodeInFilmSeries    = errors.New("episode cannot belong to a film series")
	ErrEpisodeInFranchise     = errors.New("episode cannot belong to a franchise")
	ErrMovieInSeason          = errors.New("movie cannot be added as an episode")
	ErrMediaNotMovie          = errors.New("media is not a movie")
	ErrMovieInFranchise       = errors.New("movie is already a standalone franchise entry")
	ErrFranchiseMediaInWork   = errors.New("movie already belongs to a film series")
	ErrDuplicateWorkItem      = errors.New("media already exists in this work")
	ErrDuplicateSeason        = errors.New("season number already exists")
	ErrInvalidOrder           = errors.New("order must contain every item exactly once")
)

// WorkStore — глобальный каталог сериалов и серий фильмов.
type WorkStore struct {
	db *gorm.DB
}

func NewWorkRepository(db *gorm.DB) *WorkStore {
	return &WorkStore{db: db}
}

// Create создаёт work. Для series в той же транзакции создаётся Сезон 1:
// сериал без сезона невозможен.
func (r *WorkStore) Create(ctx context.Context, work *models.Work) error {
	if !work.Kind.Valid() {
		return ErrInvalidWorkKind
	}
	if work.Title == "" {
		return ErrWorkTitleRequired
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(work).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindSeries {
			return nil
		}
		season := models.Season{
			WorkID:       work.ID,
			SeasonNumber: 1,
			Position:     0,
		}
		return tx.Create(&season).Error
	})
}

func (r *WorkStore) List(ctx context.Context, kind models.WorkKind) ([]models.Work, error) {
	q := r.db.WithContext(ctx).Order("title ASC, id ASC")
	if kind != "" {
		if !kind.Valid() {
			return nil, ErrInvalidWorkKind
		}
		q = q.Where("kind = ?", kind)
	}
	var works []models.Work
	err := q.Find(&works).Error
	return works, err
}

// Get загружает work с сезонами, эпизодами и фильмами film_series.
func (r *WorkStore) Get(ctx context.Context, id uint) (*models.Work, error) {
	var work models.Work
	db := r.db.WithContext(ctx)
	if err := db.First(&work, id).Error; err != nil {
		return nil, err
	}
	if err := db.Where("work_id = ?", id).
		Order("position ASC, id ASC").Find(&work.Seasons).Error; err != nil {
		return nil, err
	}
	all := make([]*models.WorkItem, 0)
	for i := range work.Seasons {
		if err := db.Where("season_id = ?", work.Seasons[i].ID).
			Order("position ASC, id ASC").Find(&work.Seasons[i].Items).Error; err != nil {
			return nil, err
		}
		for j := range work.Seasons[i].Items {
			all = append(all, &work.Seasons[i].Items[j])
		}
	}
	if err := db.Where("work_id = ?", id).
		Order("position ASC, id ASC").Find(&work.Items).Error; err != nil {
		return nil, err
	}
	for i := range work.Items {
		all = append(all, &work.Items[i])
	}
	if err := r.attachMedia(ctx, all); err != nil {
		return nil, err
	}
	return &work, nil
}

// GetSeason возвращает сезон с эпизодами и Media — для ответа после update.
func (r *WorkStore) GetSeason(ctx context.Context, id uint) (*models.Season, error) {
	var season models.Season
	db := r.db.WithContext(ctx)
	if err := db.First(&season, id).Error; err != nil {
		return nil, err
	}
	if err := db.Where("season_id = ?", id).
		Order("position ASC, id ASC").Find(&season.Items).Error; err != nil {
		return nil, err
	}
	items := make([]*models.WorkItem, 0, len(season.Items))
	for i := range season.Items {
		items = append(items, &season.Items[i])
	}
	if err := r.attachMedia(ctx, items); err != nil {
		return nil, err
	}
	return &season, nil
}

// GetItem возвращает элемент с подгруженным Media.
func (r *WorkStore) GetItem(ctx context.Context, id uint) (*models.WorkItem, error) {
	var item models.WorkItem
	if err := r.db.WithContext(ctx).First(&item, id).Error; err != nil {
		return nil, err
	}
	if err := r.attachMedia(ctx, []*models.WorkItem{&item}); err != nil {
		return nil, err
	}
	return &item, nil
}

func (r *WorkStore) attachMedia(ctx context.Context, items []*models.WorkItem) error {
	if len(items) == 0 {
		return nil
	}
	ids := make([]uint, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.MediaID)
	}
	var media []models.Media
	if err := r.db.WithContext(ctx).Where("id IN ?", ids).Find(&media).Error; err != nil {
		return err
	}
	byID := make(map[uint]*models.Media, len(media))
	for i := range media {
		byID[media[i].ID] = &media[i]
	}
	for _, item := range items {
		item.Media = byID[item.MediaID]
	}
	return nil
}

type WorkPatch struct {
	Title       *string
	Description *string
	CoverURL    *string
	Year        *int
}

func (r *WorkStore) Update(ctx context.Context, id uint, patch WorkPatch) (*models.Work, error) {
	updates := map[string]any{}
	if patch.Title != nil {
		if *patch.Title == "" {
			return nil, ErrWorkTitleRequired
		}
		updates["title"] = *patch.Title
	}
	if patch.Description != nil {
		updates["description"] = *patch.Description
	}
	if patch.CoverURL != nil {
		updates["cover_url"] = *patch.CoverURL
	}
	if patch.Year != nil {
		updates["year"] = *patch.Year
	}
	if len(updates) > 0 {
		if err := r.db.WithContext(ctx).Model(&models.Work{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			return nil, err
		}
	}
	return r.Get(ctx, id)
}

// Delete удаляет work и его каталог каскадом. Media не удаляются.
// Эпизоды сериала, потерявшие сезон, снова становятся фильмами.
func (r *WorkStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var work models.Work
		if err := tx.First(&work, id).Error; err != nil {
			return err
		}
		var mediaIDs []uint
		if work.Kind == models.WorkKindSeries {
			var seasonIDs []uint
			if err := tx.Model(&models.Season{}).Where("work_id = ?", id).
				Pluck("id", &seasonIDs).Error; err != nil {
				return err
			}
			if len(seasonIDs) > 0 {
				if err := tx.Model(&models.WorkItem{}).Where("season_id IN ?", seasonIDs).
					Pluck("media_id", &mediaIDs).Error; err != nil {
					return err
				}
			}
		}
		if err := tx.Unscoped().Delete(&models.Work{}, id).Error; err != nil {
			return err
		}
		return resetEpisodesToMovies(tx, mediaIDs)
	})
}

// CreateSeason добавляет сезон в сериал.
func (r *WorkStore) CreateSeason(ctx context.Context, workID uint, seasonNumber int, title string) (*models.Season, error) {
	if seasonNumber < 0 {
		return nil, ErrSeasonNumberInvalid
	}
	var season models.Season
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var work models.Work
		if err := tx.First(&work, workID).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindSeries {
			return ErrNotSeries
		}
		var maxPos int
		if err := tx.Model(&models.Season{}).Where("work_id = ?", workID).
			Select("COALESCE(MAX(position), -1)").Scan(&maxPos).Error; err != nil {
			return err
		}
		season = models.Season{
			WorkID: workID, SeasonNumber: seasonNumber, Title: title, Position: maxPos + 1,
		}
		if err := tx.Create(&season).Error; err != nil {
			if isUniqueViolation(err) {
				return ErrDuplicateSeason
			}
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &season, nil
}

type SeasonPatch struct {
	SeasonNumber *int
	Title        *string
}

func (r *WorkStore) UpdateSeason(ctx context.Context, id uint, patch SeasonPatch) (*models.Season, error) {
	updates := map[string]any{}
	if patch.SeasonNumber != nil {
		if *patch.SeasonNumber < 0 {
			return nil, ErrSeasonNumberInvalid
		}
		updates["season_number"] = *patch.SeasonNumber
	}
	if patch.Title != nil {
		updates["title"] = *patch.Title
	}
	if len(updates) > 0 {
		if err := r.db.WithContext(ctx).Model(&models.Season{}).Where("id = ?", id).Updates(updates).Error; err != nil {
			if isUniqueViolation(err) {
				return nil, ErrDuplicateSeason
			}
			return nil, err
		}
	}
	var season models.Season
	if err := r.db.WithContext(ctx).First(&season, id).Error; err != nil {
		return nil, err
	}
	return &season, nil
}

// DeleteSeason удаляет сезон; последний сезон сериала удалить нельзя.
// Эпизоды сезона, у которых не осталось другого сезона, снова movie.
func (r *WorkStore) DeleteSeason(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var season models.Season
		if err := tx.First(&season, id).Error; err != nil {
			return err
		}
		var work models.Work
		if err := tx.First(&work, season.WorkID).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindSeries {
			return ErrNotSeries
		}
		var count int64
		if err := tx.Model(&models.Season{}).Where("work_id = ?", season.WorkID).Count(&count).Error; err != nil {
			return err
		}
		if count <= 1 {
			return ErrLastSeason
		}
		var mediaIDs []uint
		if err := tx.Model(&models.WorkItem{}).Where("season_id = ?", id).
			Pluck("media_id", &mediaIDs).Error; err != nil {
			return err
		}
		if err := tx.Unscoped().Delete(&models.Season{}, id).Error; err != nil {
			return err
		}
		return resetEpisodesToMovies(tx, mediaIDs)
	})
}

// ReorderSeasons принимает полный список ID сезонов work.
func (r *WorkStore) ReorderSeasons(ctx context.Context, workID uint, ids []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var work models.Work
		if err := tx.First(&work, workID).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindSeries {
			return ErrNotSeries
		}
		var existing []models.Season
		if err := tx.Where("work_id = ?", workID).Find(&existing).Error; err != nil {
			return err
		}
		if !sameIDSet(existing, ids) {
			return ErrInvalidOrder
		}
		for pos, id := range ids {
			if err := tx.Model(&models.Season{}).Where("id = ?", id).
				Update("position", pos).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

// AddEpisode добавляет видео в сезон и переводит его в episode.
func (r *WorkStore) AddEpisode(ctx context.Context, seasonID, mediaID uint, episodeNumber *int) (*models.WorkItem, error) {
	var item models.WorkItem
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var season models.Season
		if err := tx.First(&season, seasonID).Error; err != nil {
			return err
		}
		var work models.Work
		if err := tx.First(&work, season.WorkID).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindSeries {
			return ErrNotSeries
		}
		var media models.Media
		if err := tx.First(&media, mediaID).Error; err != nil {
			return err
		}
		if media.Type != models.MediaTypeVideo {
			return ErrMediaNotVideo
		}
		var franchiseCount int64
		if err := tx.Model(&models.FranchiseEntry{}).Where("media_id = ?", mediaID).
			Count(&franchiseCount).Error; err != nil {
			return err
		}
		if franchiseCount > 0 {
			return ErrEpisodeInFranchise
		}
		var membership models.WorkItem
		err := tx.Where("media_id = ?", mediaID).First(&membership).Error
		switch {
		case err == nil && membership.SeasonID != nil:
			return ErrEpisodeAlreadyInSeason
		case err == nil && membership.WorkID != nil:
			return ErrEpisodeInFilmSeries
		case err != nil && !errors.Is(err, gorm.ErrRecordNotFound):
			return err
		}
		var maxPos int
		if err := tx.Model(&models.WorkItem{}).Where("season_id = ?", seasonID).
			Select("COALESCE(MAX(position), -1)").Scan(&maxPos).Error; err != nil {
			return err
		}
		item = models.WorkItem{SeasonID: &seasonID, MediaID: mediaID, EpisodeNumber: episodeNumber, Position: maxPos + 1}
		if err := tx.Create(&item).Error; err != nil {
			if isUniqueViolation(err) {
				return ErrDuplicateWorkItem
			}
			return err
		}
		return tx.Model(&models.Media{}).Where("id = ?", mediaID).
			Update("video_kind", models.VideoKindEpisode).Error
	})
	if err != nil {
		return nil, err
	}
	return &item, nil
}

// AddFilm добавляет фильм в film_series.
func (r *WorkStore) AddFilm(ctx context.Context, workID, mediaID uint) (*models.WorkItem, error) {
	var item models.WorkItem
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var work models.Work
		if err := tx.First(&work, workID).Error; err != nil {
			return err
		}
		if work.Kind != models.WorkKindFilmSeries {
			return ErrNotFilmSeries
		}
		var media models.Media
		if err := tx.First(&media, mediaID).Error; err != nil {
			return err
		}
		if media.Type != models.MediaTypeVideo {
			return ErrMediaNotVideo
		}
		var seasonMembership models.WorkItem
		err := tx.Where("media_id = ? AND season_id IS NOT NULL", mediaID).
			First(&seasonMembership).Error
		if err == nil {
			return ErrMovieInSeason
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		var existing models.WorkItem
		err = tx.Where("work_id = ? AND media_id = ?", workID, mediaID).
			First(&existing).Error
		if err == nil {
			return ErrDuplicateWorkItem
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		if media.VideoKind != nil && *media.VideoKind != models.VideoKindMovie {
			return ErrMediaNotMovie
		}
		var franchiseCount int64
		if err := tx.Model(&models.FranchiseEntry{}).Where("media_id = ?", mediaID).
			Count(&franchiseCount).Error; err != nil {
			return err
		}
		if franchiseCount > 0 {
			return ErrMovieInFranchise
		}
		var maxPos int
		if err := tx.Model(&models.WorkItem{}).Where("work_id = ?", workID).
			Select("COALESCE(MAX(position), -1)").Scan(&maxPos).Error; err != nil {
			return err
		}
		item = models.WorkItem{WorkID: &workID, MediaID: mediaID, Position: maxPos + 1}
		if err := tx.Create(&item).Error; err != nil {
			if isUniqueViolation(err) {
				return ErrDuplicateWorkItem
			}
			return err
		}
		return tx.Model(&models.Media{}).Where("id = ?", mediaID).
			Update("video_kind", models.VideoKindMovie).Error
	})
	if err != nil {
		return nil, err
	}
	return &item, nil
}

// RemoveEpisode удаляет эпизод из сезона. Если это была последняя сезонная
// привязка, видео снова становится самостоятельным фильмом.
func (r *WorkStore) RemoveEpisode(ctx context.Context, seasonID, mediaID uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Where("season_id = ? AND media_id = ?", seasonID, mediaID).
			Delete(&models.WorkItem{})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return resetEpisodesToMovies(tx, []uint{mediaID})
	})
}

func (r *WorkStore) RemoveFilm(ctx context.Context, workID, mediaID uint) error {
	res := r.db.WithContext(ctx).Where("work_id = ? AND media_id = ?", workID, mediaID).
		Delete(&models.WorkItem{})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ReorderSeasonItems принимает полный список ID work_items сезона.
func (r *WorkStore) ReorderSeasonItems(ctx context.Context, seasonID uint, ids []uint) error {
	var season models.Season
	if err := r.db.WithContext(ctx).First(&season, seasonID).Error; err != nil {
		return err
	}
	var work models.Work
	if err := r.db.WithContext(ctx).First(&work, season.WorkID).Error; err != nil {
		return err
	}
	if work.Kind != models.WorkKindSeries {
		return ErrNotSeries
	}
	return r.reorderItems(ctx, "season_id", seasonID, ids)
}

// ReorderWorkItems принимает полный список ID work_items film_series.
func (r *WorkStore) ReorderWorkItems(ctx context.Context, workID uint, ids []uint) error {
	var work models.Work
	if err := r.db.WithContext(ctx).First(&work, workID).Error; err != nil {
		return err
	}
	if work.Kind != models.WorkKindFilmSeries {
		return ErrNotFilmSeries
	}
	return r.reorderItems(ctx, "work_id", workID, ids)
}

func (r *WorkStore) reorderItems(ctx context.Context, column string, parentID uint, ids []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var existing []models.WorkItem
		if err := tx.Where(column+" = ?", parentID).Find(&existing).Error; err != nil {
			return err
		}
		if !sameWorkItemSet(existing, ids) {
			return ErrInvalidOrder
		}
		for pos, id := range ids {
			if err := tx.Model(&models.WorkItem{}).Where("id = ?", id).
				Update("position", pos).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

// resetEpisodesToMovies возвращает эпизоды без сезона в самостоятельные
// фильмы. Чужие kind не трогает; триггер media_video_kind остаётся валидным.
func resetEpisodesToMovies(tx *gorm.DB, mediaIDs []uint) error {
	for _, mediaID := range mediaIDs {
		var count int64
		if err := tx.Model(&models.WorkItem{}).
			Where("media_id = ? AND season_id IS NOT NULL", mediaID).Count(&count).Error; err != nil {
			return err
		}
		if count > 0 {
			continue
		}
		if err := tx.Model(&models.Media{}).
			Where("id = ? AND type = ? AND video_kind = ?", mediaID, models.MediaTypeVideo, models.VideoKindEpisode).
			Update("video_kind", models.VideoKindMovie).Error; err != nil {
			return err
		}
	}
	return nil
}

func sameIDSet(rows []models.Season, ids []uint) bool {
	if len(rows) != len(ids) {
		return false
	}
	want := make(map[uint]struct{}, len(ids))
	for _, id := range ids {
		want[id] = struct{}{}
	}
	if len(want) != len(ids) {
		return false
	}
	for _, row := range rows {
		if _, ok := want[row.ID]; !ok {
			return false
		}
	}
	return true
}

func sameWorkItemSet(rows []models.WorkItem, ids []uint) bool {
	if len(rows) != len(ids) {
		return false
	}
	want := make(map[uint]struct{}, len(ids))
	for _, id := range ids {
		want[id] = struct{}{}
	}
	if len(want) != len(ids) {
		return false
	}
	for _, row := range rows {
		if _, ok := want[row.ID]; !ok {
			return false
		}
	}
	return true
}

// (isUniqueViolation живёт в db.go: общий SQLite-детектор UNIQUE.)

// MediaCatalogContext — где медиа участвует в глобальном каталоге.
// Возвращается отдельным запросом, чтобы не раздувать Media.
type MediaCatalogContext struct {
	WorkID        *uint              `json:"work_id,omitempty"`
	WorkTitle     string             `json:"work_title,omitempty"`
	WorkKind      models.WorkKind    `json:"work_kind,omitempty"`
	SeasonID      *uint              `json:"season_id,omitempty"`
	SeasonNumber  int                `json:"season_number,omitempty"`
	EpisodeNumber *int               `json:"episode_number,omitempty"`
	Franchises    []FranchiseContext `json:"franchises"`
}

type FranchiseContext struct {
	ID   uint   `json:"id"`
	Name string `json:"name"`
}

func (r *WorkStore) GetMediaContext(ctx context.Context, mediaID uint) (*MediaCatalogContext, error) {
	result := &MediaCatalogContext{Franchises: []FranchiseContext{}}
	var item models.WorkItem
	err := r.db.WithContext(ctx).Where("media_id = ?", mediaID).First(&item).Error
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}
	if err == nil {
		if item.SeasonID != nil {
			var season models.Season
			if err := r.db.WithContext(ctx).First(&season, *item.SeasonID).Error; err != nil {
				return nil, err
			}
			var work models.Work
			if err := r.db.WithContext(ctx).First(&work, season.WorkID).Error; err != nil {
				return nil, err
			}
			result.WorkID = &work.ID
			result.WorkTitle = work.Title
			result.WorkKind = work.Kind
			result.SeasonID = &season.ID
			result.SeasonNumber = season.SeasonNumber
			result.EpisodeNumber = item.EpisodeNumber
		} else if item.WorkID != nil {
			var work models.Work
			if err := r.db.WithContext(ctx).First(&work, *item.WorkID).Error; err != nil {
				return nil, err
			}
			result.WorkID = &work.ID
			result.WorkTitle = work.Title
			result.WorkKind = work.Kind
		}
	}
	entryQuery := r.db.WithContext(ctx).Model(&FranchiseContext{}).
		Table("franchise_entries").
		Select("DISTINCT franchises.id, franchises.name").
		Joins("JOIN franchises ON franchises.id = franchise_entries.franchise_id")
	if result.WorkID != nil {
		entryQuery = entryQuery.Where(
			"franchise_entries.media_id = ? OR franchise_entries.work_id = ?",
			mediaID, *result.WorkID,
		)
	} else {
		entryQuery = entryQuery.Where("franchise_entries.media_id = ?", mediaID)
	}
	if err := entryQuery.Order("franchises.name ASC, franchises.id ASC").
		Scan(&result.Franchises).Error; err != nil {
		return nil, err
	}
	return result, nil
}
