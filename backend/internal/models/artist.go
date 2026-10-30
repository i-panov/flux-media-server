package models

import "time"

// Artist represents a music artist or creator.
type Artist struct {
	ID   uint   `gorm:"primaryKey" json:"id"`
	Name string `gorm:"size:255" json:"name"`
	// NameNorm — нормализованное имя (trim + lower) с UNIQUE-индексом:
	// сравнение в SQLite бинарное, без него «Кино» и «кино» плодили
	// дубли. Заполняется кодом (Go lower — юникодный, в отличие от
	// SQLite LOWER), не триггером.
	NameNorm string `gorm:"uniqueIndex:idx_artists_name_norm;size:255" json:"-"`
	// HasCover — признак наличия файла обложки на диске. Заполняется
	// хендлером (stat по файлу), в БД не хранится.
	HasCover  bool      `gorm:"-" json:"has_cover"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// MediaArtist is the join table between Media and Artist with a position
// for ordering artists on a track. Уникальность пары (media_id, artist_id)
// обеспечивается составным первичным ключом, отдельный uniqueIndex не нужен.
type MediaArtist struct {
	MediaID  uint `gorm:"primaryKey" json:"media_id"`
	ArtistID uint `gorm:"primaryKey" json:"artist_id"`
	Position int  `gorm:"default:0" json:"position"`
}

// ArtistLink is a row from media_artists JOIN artists, used by the
// repository to attach artists to media in the correct position order
// without GORM's many2many preload (which cannot ORDER BY a join-table
// column and would require a manual JOIN that causes duplicate artists
// via a cartesian product across all media_artists rows of each artist).
type ArtistLink struct {
	MediaID  uint   `gorm:"column:media_id"`
	ArtistID uint   `gorm:"column:artist_id"`
	Name     string `gorm:"column:name"`
	Position int    `gorm:"column:position"`
}
