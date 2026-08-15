package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"flux/internal/models"

	"gorm.io/gorm"
)

// ErrArtistNameTaken — переименование артиста в уже занятое имя.
var ErrArtistNameTaken = errors.New("artist name already taken")

type ArtistStore struct {
	db *gorm.DB
}

func NewArtistRepository(db *gorm.DB) *ArtistStore {
	return &ArtistStore{db: db}
}

// FindAll returns all artists ordered by name.
func (r *ArtistStore) FindAll(ctx context.Context) ([]models.Artist, error) {
	var artists []models.Artist
	err := r.db.WithContext(ctx).Order("name ASC").Find(&artists).Error
	return artists, err
}

// FindByID returns an artist by ID.
func (r *ArtistStore) FindByID(ctx context.Context, id uint) (*models.Artist, error) {
	var artist models.Artist
	err := r.db.WithContext(ctx).First(&artist, id).Error
	return &artist, err
}

// Update переименовывает артиста. Имя уникально — при конфликте
// возвращается ErrArtistNameTaken. Привязки media_artists ссылаются по
// id, поэтому новое имя автоматически применяется ко всем трекам.
func (r *ArtistStore) Update(ctx context.Context, id uint, name string) (*models.Artist, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("artist name is empty")
	}

	result := r.db.WithContext(ctx).
		Model(&models.Artist{}).
		Where("id = ?", id).
		Update("name", name)
	if result.Error != nil {
		if isUniqueViolation(result.Error) {
			return nil, ErrArtistNameTaken
		}
		return nil, result.Error
	}
	if result.RowsAffected == 0 {
		return nil, gorm.ErrRecordNotFound
	}
	return r.FindByID(ctx, id)
}

// Touch обновляет updated_at артиста. Нужно для cache-buster'а обложки:
// клиент строит URL картинки с ?v=updated_at, поэтому при смене файла
// обложки отметка времени обязана измениться.
func (r *ArtistStore) Touch(ctx context.Context, id uint) error {
	result := r.db.WithContext(ctx).
		Model(&models.Artist{}).
		Where("id = ?", id).
		Update("updated_at", time.Now())
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// FindOrCreateByName finds an artist by name or creates a new one.
// Name is trimmed; empty names are rejected.
func (r *ArtistStore) FindOrCreateByName(ctx context.Context, name string) (*models.Artist, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, errors.New("artist name is empty")
	}

	var artist models.Artist
	err := r.db.WithContext(ctx).Where("name = ?", name).First(&artist).Error
	if err == nil {
		return &artist, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	artist = models.Artist{Name: name}
	if err := r.db.WithContext(ctx).Create(&artist).Error; err != nil {
		// Гонка: такой артист уже создан конкурентным запросом. Маскируем
		// ошибку только если это UNIQUE-нарушение и запись теперь существует;
		// реальные сбои БД возвращаются как есть.
		if !isUniqueViolation(err) {
			return nil, err
		}
		if err2 := r.db.WithContext(ctx).Where("name = ?", name).First(&artist).Error; err2 != nil {
			return nil, err
		}
	}
	return &artist, nil
}

// LoadArtistsForMedia attaches artists to each media record in a single
// query, ordered by the join-table position column.
//
// This replaces GORM's many2many Preload for the Artists relation because:
//  1. GORM's many2many preload cannot ORDER BY a join-table column
//     (media_artists.position) — the artists query doesn't include the
//     join table.
//  2. Adding a manual JOIN media_artists inside the preload function
//     causes DUPLICATE artists: the JOIN is not scoped to the current
//     media, so an artist linked to N media produces N rows, all of which
//     GORM appends to every media that references that artist (cartesian
//     product).
//
// The manual query here is media-scoped (WHERE media_artists.media_id IN
// (...)) so each artist appears exactly once per media it belongs to.
func LoadArtistsForMedia(db *gorm.DB, media []models.Media) error {
	if len(media) == 0 {
		return nil
	}

	ids := make([]uint, 0, len(media))
	for _, m := range media {
		ids = append(ids, m.ID)
	}

	var links []models.ArtistLink
	err := db.Table("media_artists").
		Select("media_artists.media_id, media_artists.artist_id, artists.name, media_artists.position").
		Joins("JOIN artists ON artists.id = media_artists.artist_id").
		Where("media_artists.media_id IN ?", ids).
		Order("media_artists.media_id ASC, media_artists.position ASC").
		Scan(&links).Error
	if err != nil {
		return err
	}

	byMedia := make(map[uint][]models.Artist, len(media))
	for _, l := range links {
		byMedia[l.MediaID] = append(byMedia[l.MediaID], models.Artist{
			ID:   l.ArtistID,
			Name: l.Name,
		})
	}
	for i := range media {
		if arts, ok := byMedia[media[i].ID]; ok {
			media[i].Artists = arts
		} else {
			media[i].Artists = []models.Artist{}
		}
	}
	return nil
}
