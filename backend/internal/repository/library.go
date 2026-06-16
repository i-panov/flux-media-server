package repository

import (
	"flux/internal/models"

	"gorm.io/gorm"
)

type LibraryRepository struct {
	db *gorm.DB
}

func NewLibraryRepository(db *gorm.DB) *LibraryRepository {
	return &LibraryRepository{db: db}
}

func (r *LibraryRepository) FindAll() ([]models.MediaLibrary, error) {
	var libraries []models.MediaLibrary
	err := r.db.Find(&libraries).Error
	return libraries, err
}

func (r *LibraryRepository) FindByID(id uint) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.First(&library, id).Error
	return &library, err
}

func (r *LibraryRepository) FindByPath(path string) (*models.MediaLibrary, error) {
	var library models.MediaLibrary
	err := r.db.Where("path = ?", path).First(&library).Error
	return &library, err
}

func (r *LibraryRepository) Create(library *models.MediaLibrary) error {
	return r.db.Create(library).Error
}

func (r *LibraryRepository) Update(library *models.MediaLibrary) error {
	return r.db.Save(library).Error
}

func (r *LibraryRepository) Delete(id uint) error {
	return r.db.Delete(&models.MediaLibrary{}, id).Error
}
