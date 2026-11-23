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
	Type        MediaType `gorm:"index;type:text" json:"type"` // video, audio, image
	// VideoKind — movie/episode. NULL для audio/image; для видео задаётся
	// каталогом/загрузкой. Nullable: старые видео мигрируются как movie.
	VideoKind *VideoKind `gorm:"column:video_kind;type:text;index" json:"video_kind,omitempty"`
	// constraint на many2many создаёт FK на join-таблице media_artists
	// (media_id → media.id, artist_id → artists.id) с каскадами — но только
	// на свежих БД; старые БД не пересоздаются (ручные каскады в
	// repository.MediaStore.Delete покрывают их).
	Artists     []Artist `gorm:"many2many:media_artists;constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"artists"`
	Album       string   `json:"album"`
	AlbumArtist string   `json:"album_artist"`
	Composer    string   `json:"composer"`
	TrackNumber int      `json:"track_number"`
	DiscNumber  int      `json:"disc_number"`
	Genre       string   `json:"genre"`
	Duration    int      `json:"duration"` // seconds
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
	FilePath string `gorm:"index" json:"-"`
	FileSize int64  `json:"file_size"`
	FileHash string `gorm:"index" json:"file_hash"`
	// PHash — perceptual hash мема (64 бита), считается с превью.
	// 0 — хэш ещё не посчитан; в JSON не отдаётся.
	PHash int64 `gorm:"column:phash" json:"-"`
	// SourceHash — sha256 исходника в карантине, из которого получен
	// этот файл (нормализация). У direct-файлов совпадает с FileHash.
	// Нужен для дедупа повторных заливок: хэш результата отличается.
	SourceHash string `gorm:"index" json:"-"`
	QuickHash  string `gorm:"index" json:"quick_hash"`
	// ViewCount — счётчик стартов стриминга. Только для сортировки
	// в админке (чистка оригиналов), не для пользовательских топов.
	ViewCount    uint64 `json:"view_count"`
	ThumbnailURL string `json:"thumbnail_url"`
	CoverURL     string `json:"cover_url"`
	// CoverAttempted — встроенную обложку уже пытались извлечь.
	CoverAttempted bool `gorm:"not null;default:false" json:"-"`
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
	SourceMediaID *uint `gorm:"index" json:"source_media_id,omitempty"`
	// ClipSourceMediaID — ID медиа, из которого вырезан этот фрагмент
	// (POST /api/media/:id/clip). Отдельно от SourceMediaID: тот означает
	// «аудиодорожка, извлечённая из видео», и смешивать их нельзя —
	// экран видео искал бы видеоклип вместо трека.
	ClipSourceMediaID *uint     `gorm:"index" json:"clip_source_media_id,omitempty"`
	MetadataID        *uint     `json:"metadata_id,omitempty"`
	Metadata          *Metadata `json:"metadata,omitempty"`
	// Tags заполняется репозиторием отдельным запросом (gorm:"-"):
	// карточкам нужны бейджи, но постоянная связь в preload дорога.
	Tags      []Tag          `gorm:"-" json:"tags,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
	// AutoTrashed — запись убрана сканером из-за пропажи файла, а не
	// пользователем. Purge такой записи не удаляет файлы с диска: файл
	// мог вернуться, а строка осталась в корзине. Пользовательская
	// корзина (MediaStore.Delete) всегда ставит false.
	AutoTrashed bool `gorm:"default:false" json:"-"`
}

// BeforeCreate задаёт video_kind для видео, если вызывающий его не указал.
// Для audio/image значение всегда NULL: инвариант держат триггеры СУБД.
func (m *Media) BeforeCreate(tx *gorm.DB) error {
	if m.Type == MediaTypeVideo && m.VideoKind == nil {
		kind := VideoKindMovie
		m.VideoKind = &kind
	}
	if m.Type != MediaTypeVideo {
		m.VideoKind = nil
	}
	return nil
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
