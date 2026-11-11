package handlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/config"
	"flux/internal/handlers"
	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
)

type adminUsersFixture struct {
	app          *fiber.App
	db           *gorm.DB
	userRepo     repository.UserRepository
	mediaRepo    repository.MediaRepository
	colRepo      repository.CollectionRepository
	itemRepo     repository.CollectionItemRepository
	favRepo      repository.FavoriteRepository
	progressRepo repository.ProgressRepository
	refreshRepo  repository.RefreshTokenRepository
}

func setupAdminUsersTestApp(t *testing.T, authUserID uint) *adminUsersFixture {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	userRepo := repository.NewUserRepository(db)
	mediaRepo := repository.NewMediaRepository(db)
	colRepo := repository.NewCollectionRepository(db)
	itemRepo := repository.NewCollectionItemRepository(db)
	favRepo := repository.NewFavoriteRepository(db)
	progressRepo := repository.NewProgressRepository(db)
	refreshRepo := repository.NewRefreshTokenRepository(db)

	ctx := context.Background()
	require.NoError(t, userRepo.Create(ctx, &models.User{ID: 1, Email: "admin@test.com"}))
	require.NoError(t, userRepo.Create(ctx, &models.User{ID: 2, Email: "user@test.com"}))

	handler := handlers.NewAdminHandler(mediaRepo, nil, nil, config.StorageConfig{}, config.MediaConfig{}, userRepo, nil)
	app := fiber.New()
	admin := app.Group("/api/admin", func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, authUserID)
		return c.Next()
	}, middleware.RequireAdmin(userRepo))
	admin.Get("/users", handler.UsersList)
	admin.Put("/users/:id", handler.UserUpdateRole)
	admin.Delete("/users/:id", handler.UserDelete)

	return &adminUsersFixture{
		app: app, db: db,
		userRepo: userRepo, mediaRepo: mediaRepo,
		colRepo: colRepo, itemRepo: itemRepo,
		favRepo: favRepo, progressRepo: progressRepo, refreshRepo: refreshRepo,
	}
}

type adminUserJSON struct {
	ID        uint   `json:"id"`
	Email     string `json:"email"`
	IsAdmin   bool   `json:"is_admin"`
	CreatedAt string `json:"created_at"`
}

func TestAdminUsersList(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)

	resp, err := fx.app.Test(httptest.NewRequest("GET", "/api/admin/users", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)

	var users []adminUserJSON
	require.NoError(t, json.Unmarshal(body, &users))
	require.Len(t, users, 2)
	assert.Equal(t, uint(1), users[0].ID)
	assert.Equal(t, "admin@test.com", users[0].Email)
	assert.True(t, users[0].IsAdmin)
	assert.NotEmpty(t, users[0].CreatedAt)
	assert.Equal(t, uint(2), users[1].ID)
	assert.Equal(t, "user@test.com", users[1].Email)
	assert.False(t, users[1].IsAdmin)
}

func TestAdminUsersListForbiddenForNonAdmin(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 2)

	resp, err := fx.app.Test(httptest.NewRequest("GET", "/api/admin/users", nil))
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}

func putRole(t *testing.T, app *fiber.App, userID uint, payload string) int {
	t.Helper()
	req := httptest.NewRequest("PUT", "/api/admin/users/"+strconv.FormatUint(uint64(userID), 10), bytes.NewReader([]byte(payload)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode
}

func TestAdminUserUpdateRole(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)
	ctx := context.Background()

	assert.Equal(t, fiber.StatusOK, putRole(t, fx.app, 2, `{"is_admin":true}`))
	got, err := fx.userRepo.FindByID(ctx, 2)
	require.NoError(t, err)
	assert.True(t, got.IsAdmin, "выдача админа чужому — ок")

	assert.Equal(t, fiber.StatusOK, putRole(t, fx.app, 2, `{"is_admin":false}`))
	got, err = fx.userRepo.FindByID(ctx, 2)
	require.NoError(t, err)
	assert.False(t, got.IsAdmin, "снятие админа с чужого — ок")

	assert.Equal(t, fiber.StatusForbidden, putRole(t, fx.app, 1, `{"is_admin":false}`))
	got, err = fx.userRepo.FindByID(ctx, 1)
	require.NoError(t, err)
	assert.True(t, got.IsAdmin, "себе снять — 4xx, флаг цел")

	assert.Equal(t, fiber.StatusBadRequest, putRole(t, fx.app, 2, `{}`))
	assert.Equal(t, fiber.StatusBadRequest, putRole(t, fx.app, 2, `not-json`))

	resp, err := fx.app.Test(httptest.NewRequest("PUT", "/api/admin/users/0", bytes.NewReader([]byte(`{"is_admin":true}`))))
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusBadRequest, resp.StatusCode)

	req := httptest.NewRequest("PUT", "/api/admin/users/999", bytes.NewReader([]byte(`{"is_admin":true}`)))
	req.Header.Set("Content-Type", "application/json")
	resp, err = fx.app.Test(req)
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

func TestAdminUserDeleteCascade(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)
	ctx := context.Background()

	mediaFile := filepath.Join(t.TempDir(), "film.mp4")
	require.NoError(t, os.WriteFile(mediaFile, []byte("video-bytes"), 0644))
	media := &models.Media{Title: "Film", Type: models.MediaTypeVideo, FilePath: mediaFile}
	require.NoError(t, fx.mediaRepo.Create(ctx, media))

	require.NoError(t, fx.db.Create(&models.Artist{ID: 1, Name: "Actor", NameNorm: "actor"}).Error)
	require.NoError(t, fx.db.Create(&models.MediaArtist{MediaID: media.ID, ArtistID: 1}).Error)

	root := &models.Collection{UserID: 2, Name: "Root", Type: models.MediaTypeVideo}
	require.NoError(t, fx.colRepo.Create(ctx, root))
	child := &models.Collection{UserID: 2, Name: "Child", Type: models.MediaTypeVideo}
	require.NoError(t, fx.colRepo.CreateWithParent(ctx, child, root.ID))
	trashed := &models.Collection{UserID: 2, Name: "Old", Type: models.MediaTypeVideo}
	require.NoError(t, fx.colRepo.Create(ctx, trashed))
	require.NoError(t, fx.colRepo.Delete(ctx, trashed.ID))
	_, err := fx.itemRepo.AddItemAtomic(ctx, root.ID, media.ID)
	require.NoError(t, err)
	_, err = fx.itemRepo.AddItemAtomic(ctx, child.ID, media.ID)
	require.NoError(t, err)

	mediaID := media.ID
	require.NoError(t, fx.favRepo.Create(ctx, &models.Favorite{UserID: 2, MediaID: &mediaID}))
	require.NoError(t, fx.progressRepo.Upsert(ctx, &models.WatchProgress{UserID: 2, MediaID: mediaID, Position: 10, Duration: 100}))
	require.NoError(t, fx.refreshRepo.Create(ctx, 2, "victim-raw-token", time.Now().Add(time.Hour)))

	adminCol := &models.Collection{UserID: 1, Name: "AdminRoot", Type: models.MediaTypeVideo}
	require.NoError(t, fx.colRepo.Create(ctx, adminCol))
	require.NoError(t, fx.favRepo.Create(ctx, &models.Favorite{UserID: 1, MediaID: &mediaID}))

	resp, err := fx.app.Test(httptest.NewRequest("DELETE", "/api/admin/users/2", nil))
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)

	_, err = fx.userRepo.FindByID(ctx, 2)
	assert.ErrorIs(t, err, gorm.ErrRecordNotFound)

	var colCount int64
	require.NoError(t, fx.db.Unscoped().Model(&models.Collection{}).Where("user_id = ?", 2).Count(&colCount).Error)
	assert.Zero(t, colCount, "коллекции жертвы снесены целиком, включая корзину")
	var itemCount int64
	require.NoError(t, fx.db.Model(&models.CollectionItem{}).Count(&itemCount).Error)
	assert.Zero(t, itemCount, "элементы коллекций жертвы удалены")
	var favCount int64
	require.NoError(t, fx.db.Model(&models.Favorite{}).Where("user_id = ?", 2).Count(&favCount).Error)
	assert.Zero(t, favCount)
	var progCount int64
	require.NoError(t, fx.db.Model(&models.WatchProgress{}).Where("user_id = ?", 2).Count(&progCount).Error)
	assert.Zero(t, progCount)
	var tokenCount int64
	require.NoError(t, fx.db.Model(&models.RefreshToken{}).Where("user_id = ?", 2).Count(&tokenCount).Error)
	assert.Zero(t, tokenCount)

	still, err := fx.mediaRepo.FindByID(ctx, mediaID)
	require.NoError(t, err)
	assert.Equal(t, "Film", still.Title, "медиа-строки не трогаем")
	st, err := os.Stat(mediaFile)
	require.NoError(t, err)
	assert.False(t, st.IsDir(), "файлы не трогаем")
	var linkCount int64
	require.NoError(t, fx.db.Model(&models.MediaArtist{}).Count(&linkCount).Error)
	assert.Equal(t, int64(1), linkCount, "чужие связи media_artists целы")

	adminCols, err := fx.colRepo.FindByUser(ctx, 1)
	require.NoError(t, err)
	assert.Len(t, adminCols, 1, "коллекции других юзеров целы")
	isFav, err := fx.favRepo.IsFavorited(ctx, 1, mediaID)
	require.NoError(t, err)
	assert.True(t, isFav, "избранное других юзеров цело")
}

func TestAdminUserDeleteSelfForbidden(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)

	resp, err := fx.app.Test(httptest.NewRequest("DELETE", "/api/admin/users/1", nil))
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)

	_, err = fx.userRepo.FindByID(context.Background(), 1)
	assert.NoError(t, err, "себя удалить — 4xx, строка цела")
}

func TestAdminUserDeleteNotFound(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)

	resp, err := fx.app.Test(httptest.NewRequest("DELETE", "/api/admin/users/999", nil))
	require.NoError(t, err)
	resp.Body.Close()
	assert.Equal(t, fiber.StatusNotFound, resp.StatusCode)
}

// stubLastAdminRepo возвращает ErrLastAdmin из SetAdmin/Delete: сам инвариант
// «последний админ» недостижим через хендлер последовательно (себя снять —
// 403 гардом раньше, чужого снять/удалить всегда оставляет себя админом),
// поэтому маппинг в 409 проверяется подменой репозитория хендлера, а
// конкурентный 409 — на уровне репозитория
// (TestUserStore_SetAdminConcurrentDemote).
type stubLastAdminRepo struct {
	repository.UserRepository
	setAdminErr error
	deleteErr   error
}

func (r *stubLastAdminRepo) SetAdmin(_ context.Context, _ uint, _ bool) error {
	return r.setAdminErr
}

func (r *stubLastAdminRepo) Delete(_ context.Context, _ uint) error {
	return r.deleteErr
}

func setupAdminUsersTestAppWithUserRepo(t *testing.T, authUserID uint, userRepo repository.UserRepository) *fiber.App {
	t.Helper()

	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)
	require.NoError(t, repository.AutoMigrate(db))

	realRepo := repository.NewUserRepository(db)
	ctx := context.Background()
	require.NoError(t, realRepo.Create(ctx, &models.User{ID: 1, Email: "admin@test.com"}))
	require.NoError(t, realRepo.Create(ctx, &models.User{ID: 2, Email: "user@test.com"}))

	handler := handlers.NewAdminHandler(nil, nil, nil, config.StorageConfig{}, config.MediaConfig{}, userRepo, nil)
	app := fiber.New()
	admin := app.Group("/api/admin", func(c *fiber.Ctx) error {
		c.Locals(middleware.LocalsUserID, authUserID)
		return c.Next()
	}, middleware.RequireAdmin(realRepo))
	admin.Put("/users/:id", handler.UserUpdateRole)
	admin.Delete("/users/:id", handler.UserDelete)
	return app
}

func TestAdminUserUpdateRoleLastAdminConflict(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)
	stub := &stubLastAdminRepo{UserRepository: fx.userRepo, setAdminErr: repository.ErrLastAdmin}
	app := setupAdminUsersTestAppWithUserRepo(t, 1, stub)

	req := httptest.NewRequest("PUT", "/api/admin/users/2", bytes.NewReader([]byte(`{"is_admin":false}`)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := app.Test(req)
	require.NoError(t, err)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
	assert.Contains(t, string(body), "last admin")
}

func TestAdminUserDeleteLastAdminConflict(t *testing.T) {
	fx := setupAdminUsersTestApp(t, 1)
	stub := &stubLastAdminRepo{UserRepository: fx.userRepo, deleteErr: repository.ErrLastAdmin}
	app := setupAdminUsersTestAppWithUserRepo(t, 1, stub)

	resp, err := app.Test(httptest.NewRequest("DELETE", "/api/admin/users/2", nil))
	require.NoError(t, err)
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusConflict, resp.StatusCode)
	assert.Contains(t, string(body), "last admin")
}
