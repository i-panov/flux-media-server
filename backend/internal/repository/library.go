package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type LibraryStore struct {
	db *gorm.DB
}

func NewLibraryRepository(db *gorm.DB) *LibraryStore {
	return &LibraryStore{db: db}
}

func (r *LibraryStore) FindAll(ctx context.Context) ([]models.MediaLibrary, error) {
	var libraries []models.MediaLibrary
	err := r.db.WithContext(ctx).Find(&libraries).Error
	return libraries, err
}

func (r *LibraryStore) FindByID(ctx context.Context, id uint) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.WithContext(ctx).First(&library, id).Error
	return &library, err
}

func (r *LibraryStore) FindByPath(ctx context.Context, path string) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.WithContext(ctx).Where("path = ?", path).First(&library).Error
	return &library, err
}

func (r *LibraryStore) Create(ctx context.Context, library *models.MediaLibrary) error {
	return r.db.WithContext(ctx).Create(library).Error
}

func (r *LibraryStore) Update(ctx context.Context, library *models.MediaLibrary) error {
	return r.db.WithContext(ctx).Save(library).Error
}

func (r *LibraryStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Delete(&models.MediaLibrary{}, id).Error
}
