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

// ErrLastAdmin — попытка оставить инстанс без администратора (снять флаг
// с единственного админа или удалить его). Хендлер отвечает 409.
var ErrLastAdmin = errors.New("repository: cannot remove the last admin")

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

// List возвращает всех пользователей по id (без пагинации:
// self-hosted, юзеров мало).
func (r *UserStore) List(ctx context.Context) ([]models.User, error) {
	var users []models.User
	err := r.db.WithContext(ctx).Order("id ASC").Find(&users).Error
	return users, err
}

// SetAdmin меняет флаг администратора. Нулевое число затронутых строк —
// gorm.ErrRecordNotFound (вызывающий отвечает 404, а не молчаливым успехом).
// Снятие флага с единственного админа — ErrLastAdmin; снять флаг с уже
// не-админа — идемпотентный успех. Транзакция BEGIN IMMEDIATE (см. _txlock
// в InitDB) сериализует конкурентные снятия: из двух параллельных снятий
// друг с друга ровно одно видит ноль других админов и получает ErrLastAdmin.
func (r *UserStore) SetAdmin(ctx context.Context, id uint, isAdmin bool) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var target models.User
		if err := tx.First(&target, id).Error; err != nil {
			return err
		}
		if !isAdmin {
			if !target.IsAdmin {
				return nil
			}
			var others int64
			if err := tx.Model(&models.User{}).Where("is_admin = ? AND id != ?", true, id).Count(&others).Error; err != nil {
				return err
			}
			if others == 0 {
				return ErrLastAdmin
			}
		}
		res := tx.Model(&models.User{}).Where("id = ?", id).Update("is_admin", isAdmin)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return nil
	})
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
// Коллекции сносятся навсегда тем же путём, что PurgeCollection: сначала
// элементы, затем строки hard-delete (Unscoped) включая корзину — обычный
// Delete оставил бы их в trash. Медиа-строки и файлы не трогаются:
// media_artists не имеет user_id и ни один запрос сюда её не задевает.
func (r *UserStore) Delete(ctx context.Context, id uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var target models.User
		if err := tx.First(&target, id).Error; err != nil {
			return err
		}
		// Удаление единственного админа оставило бы инстанс без
		// администратора — запрет внутри той же транзакции, что и каскад.
		if target.IsAdmin {
			var others int64
			if err := tx.Model(&models.User{}).Where("is_admin = ? AND id != ?", true, id).Count(&others).Error; err != nil {
				return err
			}
			if others == 0 {
				return ErrLastAdmin
			}
		}
		// Элементы коллекций пользователя (в старых БД FK отсутствует).
		if err := tx.Where("collection_id IN (SELECT id FROM collections WHERE user_id = ?)", id).
			Delete(&models.CollectionItem{}).Error; err != nil {
			return err
		}
		if err := cascadeDelete(tx, "user_id", id,
			&models.RefreshToken{}, &models.Favorite{}, &models.WatchProgress{}); err != nil {
			return err
		}
		if err := tx.Unscoped().Where("user_id = ?", id).Delete(&models.Collection{}).Error; err != nil {
			return err
		}
		res := tx.Delete(&models.User{}, id)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return nil
	})
}
