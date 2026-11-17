package models

import "time"

const (
	ImportQueued      = "queued"
	ImportDownloading = "downloading"
	ImportImporting   = "importing"
	ImportDone        = "done"
	ImportPartial     = "partial"
	ImportError       = "error"

	ImportEpisodeQueued  = "queued"
	ImportEpisodeDone    = "done"
	ImportEpisodeSkipped = "skipped"
	ImportEpisodeError   = "error"
)

// ImportJob — импорт сезона/сериала из media-loader в глобальный каталог.
type ImportJob struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	SourceURL     string    `json:"source_url"`
	Scope         string    `json:"scope"`
	Title         string    `json:"title"`
	SeriesID      string    `json:"series_id,omitempty"`
	Quality       string    `json:"quality,omitempty"`
	Format        string    `json:"format,omitempty"`
	Status        string    `gorm:"index" json:"status"`
	Stage         string    `json:"stage,omitempty"`
	Error         string    `json:"error,omitempty"`
	WorkID        uint      `json:"work_id,omitempty"`
	EpisodesTotal int       `json:"episodes_total"`
	EpisodesDone  int       `json:"episodes_done"`
	EpisodesError int       `json:"episodes_error"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// ImportEpisode — выбранная серия импорта и её состояние.
type ImportEpisode struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	ImportID    uint      `gorm:"index" json:"import_id"`
	Season      int       `json:"season"`
	Episode     int       `json:"episode"`
	Title       string    `json:"title"`
	Status      string    `gorm:"index" json:"status"`
	Error       string    `json:"error,omitempty"`
	MediaID     uint      `json:"media_id,omitempty"`
	DownloadURL string    `gorm:"-" json:"-"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
