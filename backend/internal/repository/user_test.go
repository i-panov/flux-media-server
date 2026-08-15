package repository

import (
	"context"
	"fmt"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

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
