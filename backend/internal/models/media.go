package models

import (
	"time"

	"gorm.io/gorm"
)

type Media struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	Title       string    `gorm:"index" json:"title"`
	Filename    string    `gorm:"index" json:"filename"`
	Year        int       `gorm:"index" json:"year"`
	Description string    `json:"description"`
	Type        MediaType `gorm:"index;type:text" json:"type"` // video, audio
	// constraint на many2many создаёт FK на join-таблице media_artists
	// (media_id → media.id, artist_id → artists.id) с каскадами — но только
	// на свежих БД; старые БД не пересоздаются (ручные каскады в
	// repository.MediaStore.Delete покрывают их).
	Artists  []Artist `gorm:"many2many:media_artists;constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"artists"`
	Album    string   `json:"album"`
	Genre    string   `json:"genre"`
	Duration int      `json:"duration"` // seconds
	// Width/Height — размеры видео в пикселях (0 у аудио и у файлов,
	// у которых ffprobe не отдал поток). Нужны клиенту до старта
	// воспроизведения: по соотношению сторон выбирается ориентация
	// fullscreen и пропорции встроенного превью (жёсткие 16:9 врют).
	Width  int `json:"width"`
	Height int `json:"height"`
	// FilePath is indexed (not unique): a unique index conflicts with soft
	// delete — a file re-appearing after its record was soft-deleted would
	// fail with a UNIQUE error and the media would be lost. Duplicate
	// detection is done in the scanner via FindByPath/FindByHash.
	FilePath     string `gorm:"index" json:"-"`
	FileSize     int64  `json:"file_size"`
	FileHash     string `gorm:"index" json:"file_hash"`
	QuickHash    string `gorm:"index" json:"quick_hash"`
	ThumbnailURL string `json:"thumbnail_url"`
	CoverURL     string `json:"cover_url"`
	// SourceURL — ссылка на источник (например, страница YouTube).
	// Заполняется только вручную через PUT /api/metadata/:mediaId,
	// сканер и очередь загрузок её не трогают.
	SourceURL string `json:"source_url"`
	// SourceMediaID — ID видео, из которого извлечён этот аудиотрек
	// (POST /api/media/:id/extract). NULL — обычное медиа. По связке
	// экран видео показывает «перейти к треку» вместо кнопки извлечения.
	// Индекс обычный, НЕ unique: soft-deleted строки остаются в таблице,
	// и unique заблокировал бы повторное извлечение после удаления трека.
	// Гонки закрыты дедупом in-flight джобов в ExtractService.
	SourceMediaID *uint          `gorm:"index" json:"source_media_id,omitempty"`
	MetadataID    *uint          `json:"metadata_id,omitempty"`
	Metadata      *Metadata      `json:"metadata,omitempty"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

type Metadata struct {
	ID uint `gorm:"primaryKey" json:"id"`
	// ExternalID is the ID in the external source (tmdb, ...). It is a plain
	// index (not unique): manually edited metadata has no external ID and
	// would otherwise collide on the empty value.
	ExternalID  string    `gorm:"index" json:"external_id"`
	Source      string    `json:"source"` // tmdb, tvdb
	Title       string    `json:"title"`
	Year        int       `gorm:"index" json:"year"`
	Description string    `json:"description"`
	PosterURL   string    `json:"poster_url"`
	BackdropURL string    `json:"backdrop_url"`
	Rating      float64   `json:"rating"`
	Genres      string    `json:"genres"` // JSON array
	Cast        string    `json:"cast"`   // JSON array
	CreatedAt   time.Time `json:"created_at"`
}
