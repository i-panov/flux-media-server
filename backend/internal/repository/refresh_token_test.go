package repository

import (
	"context"
	"fmt"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/models"
)

// fileDB создаёт файловую БД (не :memory:): при параллельных транзакциях
// пул открывает несколько соединений, а каждая новая connection к ":memory:"
// получает свою пустую копию БД.
func fileDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := InitDB(filepath.Join(t.TempDir(), "test.db"))
	require.NoError(t, err)
	require.NoError(t, AutoMigrate(db))
	return db
}

// TestRefreshTokenStore_RotateTokenReplay — параллельный refresh одним
// токеном: ровно один выигрывает, второй получает ErrRecordNotFound.
func TestRefreshTokenStore_RotateTokenReplay(t *testing.T) {
	db := fileDB(t)
	require.NoError(t, db.Create(&models.User{ID: 1, Email: "u1@test.com"}).Error)

	store := NewRefreshTokenRepository(db)
	ctx := context.Background()

	require.NoError(t, store.Create(ctx, 1, "token-old", time.Now().Add(time.Hour)))

	var wg sync.WaitGroup
	errs := make([]error, 2)
	start := make(chan struct{})
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			_, errs[i] = store.RotateToken(ctx, "token-old", 1,
				fmt.Sprintf("token-new-%d", i), time.Now().Add(time.Hour))
		}(i)
	}
	close(start)
	wg.Wait()

	successes := 0
	for _, err := range errs {
		if err == nil {
			successes++
		} else {
			assert.ErrorIs(t, err, gorm.ErrRecordNotFound, "проигравший запрос должен получить ErrRecordNotFound")
		}
	}
	assert.Equal(t, 1, successes, "ровно один параллельный refresh должен выиграть")
}

// TestUserStore_DeleteCascades — удаление пользователя каскадно удаляет
// refresh-токены, избранное, прогресс, коллекции и их элементы.
// Lyrics при этом остаются: они привязаны к медиа, а не к пользователю.
func TestUserStore_DeleteCascades(t *testing.T) {
	db := fileDB(t)

	userRepo := NewUserRepository(db)
	mediaRepo := NewMediaRepository(db)
	favRepo := NewFavoriteRepository(db)
	progressRepo := NewProgressRepository(db)
	refreshRepo := NewRefreshTokenRepository(db)
	colRepo := NewCollectionRepository(db)
	itemRepo := NewCollectionItemRepository(db)
	lyricsRepo := NewLyricsRepository(db)
	ctx := context.Background()

	// Данные двух пользователей — каскад должен задеть только первого.
	user := &models.User{Email: "victim@test.com"}
	require.NoError(t, userRepo.Create(ctx, user))
	other := &models.User{Email: "other@test.com"}
	require.NoError(t, userRepo.Create(ctx, other))

	media := &models.Media{Title: "Shared Movie", Type: models.MediaTypeVideo, FilePath: "/m.mkv"}
	require.NoError(t, mediaRepo.Create(ctx, media))

	require.NoError(t, favRepo.Create(ctx, &models.Favorite{UserID: user.ID, MediaID: &media.ID}))
	require.NoError(t, favRepo.Create(ctx, &models.Favorite{UserID: other.ID, MediaID: &media.ID}))
	require.NoError(t, progressRepo.Upsert(ctx, &models.WatchProgress{UserID: user.ID, MediaID: media.ID, Position: 10}))
	require.NoError(t, refreshRepo.Create(ctx, user.ID, "raw-token", time.Now().Add(time.Hour)))
	col := &models.Collection{UserID: user.ID, Name: "ToDelete"}
	require.NoError(t, colRepo.Create(ctx, col))
	require.NoError(t, itemRepo.Add(ctx, &models.CollectionItem{CollectionID: col.ID, MediaID: media.ID}))
	require.NoError(t, lyricsRepo.Upsert(ctx, &models.Lyrics{MediaID: media.ID, LyricsText: "La"}))

	require.NoError(t, userRepo.Delete(ctx, user.ID))

	count := func(model interface{}, where string, args ...interface{}) int64 {
		var n int64
		require.NoError(t, db.Model(model).Where(where, args...).Count(&n).Error)
		return n
	}

	// Пользователь удалён.
	_, err := userRepo.FindByID(ctx, user.ID)
	assert.ErrorIs(t, err, gorm.ErrRecordNotFound)

	// Все зависимые записи пользователя удалены.
	assert.Equal(t, int64(0), count(&models.RefreshToken{}, "user_id = ?", user.ID))
	assert.Equal(t, int64(0), count(&models.Favorite{}, "user_id = ?", user.ID))
	assert.Equal(t, int64(0), count(&models.WatchProgress{}, "user_id = ?", user.ID))
	assert.Equal(t, int64(0), count(&models.Collection{}, "user_id = ?", user.ID))
	assert.Equal(t, int64(0), count(&models.CollectionItem{}, "collection_id = ?", col.ID))

	// Данные других пользователей и общие данные не тронуты.
	assert.Equal(t, int64(1), count(&models.Favorite{}, "user_id = ?", other.ID))
	assert.Equal(t, int64(1), count(&models.Lyrics{}, "media_id = ?", media.ID))
}
