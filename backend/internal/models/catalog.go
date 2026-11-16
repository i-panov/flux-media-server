package models

import "time"

// WorkKind — формат глобального произведения.
type WorkKind string

const (
	WorkKindSeries     WorkKind = "series"
	WorkKindFilmSeries WorkKind = "film_series"
)

func (k WorkKind) Valid() bool {
	return k == WorkKindSeries || k == WorkKindFilmSeries
}

// VideoKind — роль видео в каталоге. Для audio/image всегда NULL.
type VideoKind string

const (
	VideoKindMovie   VideoKind = "movie"
	VideoKindEpisode VideoKind = "episode"
)

func (k VideoKind) Valid() bool {
	return k == VideoKindMovie || k == VideoKindEpisode
}

// Work — глобальный сериал или серия фильмов. Не принадлежит пользователю:
// каталог общий для инстанса, редактируется админом.
type Work struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Kind        WorkKind  `gorm:"type:text;not null;index;check:work_kind,kind IN ('series','film_series')" json:"kind"`
	Title       string    `gorm:"index" json:"title"`
	Description string    `json:"description"`
	CoverURL    string    `json:"cover_url"`
	Year        int       `gorm:"index" json:"year"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	// Заполняются репозиторием вручную: has-many associations с GORM
	// заставляли AutoMigrate пересоздавать существующие seasons/work_items
	// и терять эпизоды. gorm:"-" не даёт AutoMigrate трогать схему.
	Seasons []Season   `gorm:"-" json:"seasons,omitempty"`
	Items   []WorkItem `gorm:"-" json:"items,omitempty"`
	Tags    []Tag      `gorm:"-" json:"tags,omitempty"`
}

// Season — сезон сериала. Работает только для WorkKindSeries.
type Season struct {
	ID           uint       `gorm:"primaryKey" json:"id"`
	WorkID       uint       `gorm:"not null;uniqueIndex:idx_seasons_work_number;index:idx_seasons_work_position,priority:1" json:"work_id"`
	SeasonNumber int        `gorm:"not null;uniqueIndex:idx_seasons_work_number" json:"season_number"`
	Title        string     `json:"title"`
	Position     int        `gorm:"index:idx_seasons_work_position,priority:2" json:"position"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	Work         *Work      `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Items        []WorkItem `gorm:"-" json:"items,omitempty"`
}

// WorkItem — фильм в film_series или эпизод в season.
// Ровно одно из WorkID/SeasonID заполнено.
type WorkItem struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	WorkID        *uint     `gorm:"index:idx_work_items_work_position,priority:1;check:work_item_target,((work_id IS NULL) <> (season_id IS NULL))" json:"work_id,omitempty"`
	SeasonID      *uint     `gorm:"index:idx_work_items_season_position,priority:1" json:"season_id,omitempty"`
	MediaID       uint      `gorm:"not null;index;check:work_item_media_positive,media_id > 0" json:"media_id"`
	Position      int       `gorm:"index:idx_work_items_work_position,priority:2;index:idx_work_items_season_position,priority:2" json:"position"`
	EpisodeNumber *int      `json:"episode_number,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	// FK-ассоциации для новых БД. Каскад только от media/works/seasons;
	// удаление Work не удаляет Media.
	Work   *Work   `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Season *Season `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Media  *Media  `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"media,omitempty"`
}

// Franchise — глобальная франшиза/вселенная. Может содержать сериалы,
// серии фильмов и одиночные фильмы в едином порядке.
type Franchise struct {
	ID          uint             `gorm:"primaryKey" json:"id"`
	Name        string           `gorm:"index" json:"name"`
	Description string           `json:"description"`
	CoverURL    string           `json:"cover_url"`
	CreatedAt   time.Time        `json:"created_at"`
	UpdatedAt   time.Time        `json:"updated_at"`
	Entries     []FranchiseEntry `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"entries,omitempty"`
	Tags        []Tag            `gorm:"-" json:"tags,omitempty"`
}

// FranchiseEntry — элемент франшизы: work (series/film_series) или
// одиночный фильм. Ровно одно из WorkID/MediaID заполнено.
type FranchiseEntry struct {
	ID          uint       `gorm:"primaryKey" json:"id"`
	FranchiseID uint       `gorm:"not null;index:idx_franchise_entries_position,priority:1" json:"franchise_id"`
	WorkID      *uint      `gorm:"index;check:franchise_entry_target,((work_id IS NULL) <> (media_id IS NULL))" json:"work_id,omitempty"`
	MediaID     *uint      `gorm:"index" json:"media_id,omitempty"`
	Position    int        `gorm:"index:idx_franchise_entries_position,priority:2" json:"position"`
	CreatedAt   time.Time  `json:"created_at"`
	Franchise   *Franchise `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Work        *Work      `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"work,omitempty"`
	Media       *Media     `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"media,omitempty"`
}
