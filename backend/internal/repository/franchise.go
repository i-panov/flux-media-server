package repository

import (
	"context"
	"errors"

	"flux/internal/models"

	"gorm.io/gorm"
)

var (
	ErrFranchiseNameRequired   = errors.New("franchise name is required")
	ErrFranchiseEntryTarget    = errors.New("entry must reference exactly one work or media")
	ErrFranchiseWorkInvalid    = errors.New("franchise can contain only series and film series")
	ErrFranchiseMediaInvalid   = errors.New("franchise can contain only movies")
	ErrDuplicateFranchiseEntry = errors.New("entry already exists in this franchise")
)

// FranchiseStore — глобальные франшизы с единым порядком работ и фильмов.
type FranchiseStore struct {
	db *gorm.DB
}

func NewFranchiseRepository(db *gorm.DB) *FranchiseStore {
	return &FranchiseStore{db: db}
}

func (r *FranchiseStore) Create(ctx context.Context, franchise *models.Franchise) error {
	if franchise.Name == "" {
		return ErrFranchiseNameRequired
	}
	return r.db.WithContext(ctx).Create(franchise).Error
}

func (r *FranchiseStore) List(ctx context.Context) ([]models.Franchise, error) {
	var rows []models.Franchise
	err := r.db.WithContext(ctx).Order("name ASC, id ASC").Find(&rows).Error
	return rows, err
}

func (r *FranchiseStore) Get(ctx context.Context, id uint) (*models.Franchise, error) {
	var row models.Franchise
	err := r.db.WithContext(ctx).
		Preload("Entries", func(db *gorm.DB) *gorm.DB {
			return db.Order("franchise_entries.position ASC, franchise_entries.id ASC")
		}).
		Preload("Entries.Work").
		Preload("Entries.Media").
		First(&row, id).Error
	return &row, err
}

type FranchisePatch struct {
	Name        *string
	Description *string
	CoverURL    *string
}

func (r *FranchiseStore) GetEntry(ctx context.Context, id uint) (*models.FranchiseEntry, error) {
	var entry models.FranchiseEntry
	err := r.db.WithContext(ctx).Preload("Work").Preload("Media").First(&entry, id).Error
	return &entry, err
}

func (r *FranchiseStore) Update(ctx context.Context, id uint, patch FranchisePatch) (*models.Franchise, error) {
	updates := map[string]any{}
	if patch.Name != nil {
		if *patch.Name == "" {
			return nil, ErrFranchiseNameRequired
		}
		updates["name"] = *patch.Name
	}
	if patch.Description != nil {
		updates["description"] = *patch.Description
	}
	if patch.CoverURL != nil {
		updates["cover_url"] = *patch.CoverURL
	}
	if len(updates) > 0 {
		if err := r.db.WithContext(ctx).Model(&models.Franchise{}).Where("id = ?", id).
			Updates(updates).Error; err != nil {
			return nil, err
		}
	}
	return r.Get(ctx, id)
}

func (r *FranchiseStore) Delete(ctx context.Context, id uint) error {
	res := r.db.WithContext(ctx).Unscoped().Delete(&models.Franchise{}, id)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// AddEntry добавляет work или одиночный фильм в конец франшизы.
func (r *FranchiseStore) AddEntry(ctx context.Context, franchiseID uint, workID, mediaID *uint) (*models.FranchiseEntry, error) {
	if (workID == nil) == (mediaID == nil) {
		return nil, ErrFranchiseEntryTarget
	}
	var entry models.FranchiseEntry
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.First(&models.Franchise{}, franchiseID).Error; err != nil {
			return err
		}
		if workID != nil {
			var work models.Work
			if err := tx.First(&work, *workID).Error; err != nil {
				return err
			}
			if work.Kind != models.WorkKindSeries && work.Kind != models.WorkKindFilmSeries {
				return ErrFranchiseWorkInvalid
			}
		} else {
			var media models.Media
			if err := tx.First(&media, *mediaID).Error; err != nil {
				return err
			}
			if media.Type != models.MediaTypeVideo || media.VideoKind == nil || *media.VideoKind != models.VideoKindMovie {
				return ErrFranchiseMediaInvalid
			}
			var workCount int64
			if err := tx.Model(&models.WorkItem{}).
				Where("media_id = ?", media.ID).Count(&workCount).Error; err != nil {
				return err
			}
			if workCount > 0 {
				return ErrFranchiseMediaInWork
			}
		}
		var maxPos int
		if err := tx.Model(&models.FranchiseEntry{}).Where("franchise_id = ?", franchiseID).
			Select("COALESCE(MAX(position), -1)").Scan(&maxPos).Error; err != nil {
			return err
		}
		entry = models.FranchiseEntry{
			FranchiseID: franchiseID, WorkID: workID, MediaID: mediaID, Position: maxPos + 1,
		}
		if err := tx.Create(&entry).Error; err != nil {
			if isUniqueViolation(err) {
				return ErrDuplicateFranchiseEntry
			}
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &entry, nil
}

func (r *FranchiseStore) RemoveEntry(ctx context.Context, franchiseID, entryID uint) error {
	res := r.db.WithContext(ctx).Where("franchise_id = ?", franchiseID).
		Unscoped().Delete(&models.FranchiseEntry{}, entryID)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// ReorderEntries принимает полный список ID franchise_entries.
func (r *FranchiseStore) ReorderEntries(ctx context.Context, franchiseID uint, ids []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.First(&models.Franchise{}, franchiseID).Error; err != nil {
			return err
		}
		var existing []models.FranchiseEntry
		if err := tx.Where("franchise_id = ?", franchiseID).Find(&existing).Error; err != nil {
			return err
		}
		if len(existing) != len(ids) {
			return ErrInvalidOrder
		}
		want := make(map[uint]struct{}, len(ids))
		for _, id := range ids {
			want[id] = struct{}{}
		}
		if len(want) != len(ids) {
			return ErrInvalidOrder
		}
		for _, row := range existing {
			if _, ok := want[row.ID]; !ok {
				return ErrInvalidOrder
			}
		}
		for pos, id := range ids {
			if err := tx.Model(&models.FranchiseEntry{}).Where("id = ?", id).
				Update("position", pos).Error; err != nil {
				return err
			}
		}
		return nil
	})
}
