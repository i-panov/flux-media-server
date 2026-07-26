package repository

import (
	"flux/internal/models"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func InitDB(path string) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(path+"?_journal=WAL&_busy_timeout=5000"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})
	if err != nil {
		return nil, err
	}

	return db, nil
}

func AutoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		&models.Media{},
		&models.Metadata{},
		&models.User{},
		&models.WatchProgress{},
		&models.MediaLibrary{},
		&models.Favorite{},
		&models.Collection{},
		&models.CollectionItem{},
		&models.Lyrics{},
		&models.RefreshToken{},
	)
}
