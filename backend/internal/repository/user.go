package repository

import (
	"context"
	"errors"

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

// Create сохраняет пользователя. Бизнес-правило: первый пользователь
// становится админом. Транзакции BEGIN IMMEDIATE (см. _txlock в InitDB)
// сериализуют конкурентные регистрации, поэтому гонка двух параллельных
// «первых» пользователей невозможна; уникальный индекс на email отсекает
// дубликат той же почты.
func (r *UserStore) Create(ctx context.Context, user *models.User) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var count int64
		if err := tx.Model(&models.User{}).Count(&count).Error; err != nil {
			return err
		}
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

// Update обновляет только переданные непустые поля (email, is_admin=true).
func (r *UserStore) Update(ctx context.Context, user *models.User) error {
	if user.ID == 0 {
		return errors.New("repository: user ID required for Update")
	}
	updates := make(map[string]interface{})
	if user.Email != "" {
		updates["email"] = user.Email
	}
	if user.IsAdmin {
		updates["is_admin"] = user.IsAdmin
	}
	if len(updates) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Model(user).Updates(updates).Error
}

// Delete removes a user and cascades to all dependent rows (refresh tokens,
// favorites, watch progress, collections with their items). For старых БД,
// где FK-constraints не были созданы, каскад выполняется вручную в одной
// транзакции; для новых инсталляций это дополняется FK CASCADE.
func (r *UserStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Элементы коллекций пользователя (в старых БД FK отсутствует).
		if err := tx.Where("collection_id IN (SELECT id FROM collections WHERE user_id = ?)", id).
			Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		if err := cascadeDelete(tx, "user_id", id,
			&models.RefreshToken{}, &models.Favorite{}, &models.WatchProgress{}, &models.Collection{}); err != nil {
			return err
		}
		return tx.Delete(&models.User{}, id).Error
	})
}
