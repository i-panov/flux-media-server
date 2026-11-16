package repository

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

func TestDeviceAuthApproveConsume(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewDeviceAuthRepository(db)
	ctx := context.Background()
	require.NoError(t, db.Create(&models.User{ID: 42, Email: "device@test.com"}).Error)
	record, err := store.Create(ctx, HashDeviceCode("device"), HashDeviceCode("123456"), "tv-1", "TV", "tv", time.Now().Add(time.Minute), 3)
	require.NoError(t, err)

	pending, err := store.FindPendingByUserCode(ctx, HashDeviceCode("123456"))
	require.NoError(t, err)
	require.Equal(t, record.ID, pending.ID)

	approved, err := store.Approve(ctx, HashDeviceCode("123456"), 42)
	require.NoError(t, err)
	require.NotNil(t, approved.UserID)
	require.Equal(t, uint(42), *approved.UserID)
	require.Equal(t, models.DeviceAuthApproved, approved.Status)
	_, err = store.FindPendingByUserCode(ctx, HashDeviceCode("123456"))
	require.ErrorIs(t, err, gorm.ErrRecordNotFound)

	_, err = store.Approve(ctx, HashDeviceCode("123456"), 42)
	require.ErrorIs(t, err, ErrDeviceCodeInvalid)

	consumed, err := store.Consume(ctx, HashDeviceCode("device"))
	require.NoError(t, err)
	require.Equal(t, models.DeviceAuthConsumed, consumed.Status)
	_, err = store.Consume(ctx, HashDeviceCode("device"))
	require.ErrorIs(t, err, ErrDeviceCodeConsumed)
}

func TestDeviceAuthRejectsExpiredAndPendingConsume(t *testing.T) {
	db := setupCatalogDB(t)
	store := NewDeviceAuthRepository(db)
	ctx := context.Background()
	_, err := store.Create(ctx, HashDeviceCode("expired-device"), HashDeviceCode("654321"), "tv-2", "TV", "tv", time.Now().Add(-time.Second), 3)
	require.NoError(t, err)
	_, err = store.Approve(ctx, HashDeviceCode("654321"), 1)
	require.ErrorIs(t, err, ErrDeviceCodeInvalid)
	_, err = store.Consume(ctx, HashDeviceCode("expired-device"))
	require.ErrorIs(t, err, ErrDeviceCodeConsumed)
}
