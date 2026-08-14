package repository

import (
	"context"

	"flux/internal/models"

	"gorm.io/gorm"
)

type UserStore struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserStore {
	return &UserStore{db: db}
}

func (r *UserStore) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).Where("email = ?", email).First(&user).Error
	return &user, err
}

func (r *UserStore) FindByID(ctx context.Context, id uint) (*models.User, error) {
	var user models.User
	err := r.db.WithContext(ctx).First(&user, id).Error
	return &user, err
}

func (r *UserStore) Create(ctx context.Context, user *models.User) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var count int64
		tx.Model(&models.User{}).Count(&count)
		if count == 0 {
			user.IsAdmin = true
		}
		return tx.Create(user).Error
	})
}

// Count returns the total number of users.
func (r *UserStore) Count(ctx context.Context) (int64, error) {
	var count int64
	err := r.db.WithContext(ctx).Model(&models.User{}).Count(&count).Error
	return count, err
}

func (r *UserStore) Update(ctx context.Context, user *models.User) error {
	return r.db.WithContext(ctx).Save(user).Error
}

// Delete removes a user and cascades to all dependent rows (refresh tokens,
// favorites, watch progress, collections with their items). For старых БД,
// где FK-constraints не были созданы, каскад выполняется вручную в одной
// транзакции; для новых инсталляций это дополняется FK CASCADE.
func (r *UserStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("user_id = ?", id).Delete(&models.RefreshToken{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", id).Delete(&models.Favorite{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", id).Delete(&models.WatchProgress{}).Error; err != nil {
			return err
		}
		// Элементы коллекций пользователя (в старых БД FK отсутствует).
		if err := tx.Where("collection_id IN (SELECT id FROM collections WHERE user_id = ?)", id).
			Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", id).Delete(&models.Collection{}).Error; err != nil {
			return err
		}
		return tx.Delete(&models.User{}, id).Error
	})
}
