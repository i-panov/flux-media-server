package repository

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

// Regression test (MAJOR): ошибка Count не должна молча делать юзера админом.
func TestUserStore_FirstUserIsAdmin(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewUserRepository(db)
	ctx := context.Background()

	first := &models.User{Email: "first@test.com"}
	require.NoError(t, store.Create(ctx, first))
	assert.True(t, first.IsAdmin, "first user must become admin")

	second := &models.User{Email: "second@test.com"}
	require.NoError(t, store.Create(ctx, second))
	assert.False(t, second.IsAdmin, "second user must not become admin")

	// Дубликат email отклоняется уникальным индексом.
	dup := &models.User{Email: "first@test.com"}
	assert.Error(t, store.Create(ctx, dup), "duplicate email must fail")
}

// Regression test (MAJOR): параллельная регистрация «первых» пользователей
// не должна дать двух админов. Транзакции BEGIN IMMEDIATE сериализуют
// создание (см. _txlock в InitDB). Нужна файловая БД — конкурентные
// транзакции на :memory: получают разные копии БД.
func TestUserStore_ParallelCreateSingleAdmin(t *testing.T) {
	db := fileDB(t)

	store := NewUserRepository(db)
	ctx := context.Background()

	const n = 8
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			_ = store.Create(ctx, &models.User{Email: fmt.Sprintf("u%d@test.com", i)})
		}(i)
	}
	close(start)
	wg.Wait()

	var admins int64
	require.NoError(t, db.Model(&models.User{}).Where("is_admin = ?", true).Count(&admins).Error)
	assert.Equal(t, int64(1), admins, "exactly one admin among parallel first registrations")

	var total int64
	require.NoError(t, db.Model(&models.User{}).Count(&total).Error)
	assert.Equal(t, int64(n), total)
}

// Regression test (MAJOR): UserStore.Update не должен затирать неуказанные
// поля (старый Save писал все колонки включая нулевые).
func TestUserStore_UpdatePartialFields(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewUserRepository(db)
	ctx := context.Background()

	user := &models.User{Email: "old@test.com"}
	require.NoError(t, store.Create(ctx, user))
	require.True(t, user.IsAdmin, "first user is admin")

	// Меняем только email.
	require.NoError(t, store.Update(ctx, &models.User{ID: user.ID, Email: "new@test.com"}))

	got, err := store.FindByID(ctx, user.ID)
	require.NoError(t, err)
	assert.Equal(t, "new@test.com", got.Email)
	assert.True(t, got.IsAdmin, "is_admin must be preserved on partial update")
}

// Гонка «последний админ»: снять флаг с единственного админа нельзя —
// ErrLastAdmin, флаг цел. Снять флаг с уже-не-админа — идемпотентный успех.
func TestUserStore_SetAdminLastAdmin(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewUserRepository(db)
	ctx := context.Background()

	sole := &models.User{Email: "sole@test.com"}
	require.NoError(t, store.Create(ctx, sole))
	require.True(t, sole.IsAdmin, "first user is admin")

	assert.ErrorIs(t, store.SetAdmin(ctx, sole.ID, false), ErrLastAdmin)
	got, err := store.FindByID(ctx, sole.ID)
	require.NoError(t, err)
	assert.True(t, got.IsAdmin, "флаг единственного админа цел")

	plain := &models.User{Email: "plain@test.com"}
	require.NoError(t, store.Create(ctx, plain))
	require.NoError(t, store.SetAdmin(ctx, plain.ID, false), "false на уже-не-админа — успех")

	require.NoError(t, store.SetAdmin(ctx, plain.ID, true))
	require.NoError(t, store.SetAdmin(ctx, plain.ID, false), "обычное снятие при живом другом админе — ок")

	assert.ErrorIs(t, store.SetAdmin(ctx, 9999, false), gorm.ErrRecordNotFound)
	assert.ErrorIs(t, store.SetAdmin(ctx, 9999, true), gorm.ErrRecordNotFound)
}

// Гонка «последний админ»: два встречных снятия друг с друга из двух
// горутин за барьером — ровно одно получает ErrLastAdmin, второе успешно,
// в системе остаётся ровно один админ. Файловая БД: на :memory: у каждой
// connection своя копия данных (см. fileDB).
func TestUserStore_SetAdminConcurrentDemote(t *testing.T) {
	db := fileDB(t)

	store := NewUserRepository(db)
	ctx := context.Background()

	a := &models.User{Email: "a@test.com"}
	require.NoError(t, store.Create(ctx, a))
	b := &models.User{Email: "b@test.com"}
	require.NoError(t, store.Create(ctx, b))
	require.NoError(t, store.SetAdmin(ctx, b.ID, true))
	require.True(t, a.IsAdmin)
	gotB, err := store.FindByID(ctx, b.ID)
	require.NoError(t, err)
	require.True(t, gotB.IsAdmin, "два админа перед гонкой")

	ids := []uint{a.ID, b.ID}
	errs := make([]error, 2)
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			errs[i] = store.SetAdmin(ctx, ids[i], false)
		}(i)
	}
	close(start)
	wg.Wait()

	conflicts := 0
	for _, err := range errs {
		if errors.Is(err, ErrLastAdmin) {
			conflicts++
		} else {
			assert.NoError(t, err)
		}
	}
	assert.Equal(t, 1, conflicts, "ровно одно из двух встречных снятий — ErrLastAdmin")

	var admins int64
	require.NoError(t, db.Model(&models.User{}).Where("is_admin = ?", true).Count(&admins).Error)
	assert.Equal(t, int64(1), admins, "после гонки ровно один админ")
}

// Гонка «последний админ»: удалить единственного админа нельзя —
// ErrLastAdmin, строка цела. Обычное удаление работает.
func TestUserStore_DeleteLastAdmin(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))

	store := NewUserRepository(db)
	ctx := context.Background()

	sole := &models.User{Email: "sole@test.com"}
	require.NoError(t, store.Create(ctx, sole))

	assert.ErrorIs(t, store.Delete(ctx, sole.ID), ErrLastAdmin)
	_, err = store.FindByID(ctx, sole.ID)
	assert.NoError(t, err, "единственный админ не удалён")

	plain := &models.User{Email: "plain@test.com"}
	require.NoError(t, store.Create(ctx, plain))
	require.NoError(t, store.Delete(ctx, plain.ID), "обычное удаление не-админа — ок")

	second := &models.User{Email: "second@test.com"}
	require.NoError(t, store.Create(ctx, second))
	require.NoError(t, store.SetAdmin(ctx, second.ID, true))
	require.NoError(t, store.Delete(ctx, second.ID), "удаление админа при живом другом — ок")

	assert.ErrorIs(t, store.Delete(ctx, 9999), gorm.ErrRecordNotFound)
}
