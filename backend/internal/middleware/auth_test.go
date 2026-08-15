package middleware_test

import (
	"context"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gorm.io/gorm"

	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

func setupTestDBAndServices(t *testing.T) (*gorm.DB, repository.UserRepository, services.JWTService) {
	t.Helper()

	// Create test database
	db, err := repository.InitDB(":memory:")
	require.NoError(t, err)

	// Run migrations
	err = repository.AutoMigrate(db)
	require.NoError(t, err)

	// Create user repository
	userRepo := repository.NewUserRepository(db)

	// Create JWT service with the same secret used in other tests
	jwtService := services.NewJWTService("test-secret-that-is-at-least-32-characters-long", 24*time.Hour, 24*7*time.Hour)

	return db, userRepo, jwtService
}

func createTestUser(t *testing.T, userRepo repository.UserRepository, email string, isAdmin bool) *models.User {
	t.Helper()

	ctx := context.Background()
	user := &models.User{
		Email:   email,
		IsAdmin: isAdmin,
	}
	err := userRepo.Create(ctx, user)
	require.NoError(t, err)

	// Fetch the user to get the actual IsAdmin value
	createdUser, err := userRepo.FindByID(ctx, user.ID)
	require.NoError(t, err)
	return createdUser
}

func TestAdminMiddlewareNoToken(t *testing.T) {
	_, userRepo, jwtService := setupTestDBAndServices(t)

	// Create a test route protected by auth and admin middleware
	app := fiber.New()
	app.Get("/admin/test", middleware.AuthMiddleware(jwtService), middleware.RequireAdmin(userRepo), func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	// Make request without token
	req := httptest.NewRequest("GET", "/admin/test", nil)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
}

func TestAdminMiddlewareUserTokenOnAdminRoute(t *testing.T) {
	_, userRepo, jwtService := setupTestDBAndServices(t)

	// Create an admin user first (so the next user won't be admin)
	_ = createTestUser(t, userRepo, "admin@example.com", true)

	// Create a regular user (second user won't be auto-admin)
	regUser := createTestUser(t, userRepo, "user@example.com", false)

	// Verify the user is not admin
	require.False(t, regUser.IsAdmin, "Regular user should not be admin")

	// Generate token for regular user using the same JWT service
	token, err := jwtService.GenerateToken(regUser.ID, regUser.Email)
	require.NoError(t, err)

	// Create a test route protected by auth and admin middleware
	app := fiber.New()
	app.Get("/admin/test", middleware.AuthMiddleware(jwtService), middleware.RequireAdmin(userRepo), func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	// Make request with user token
	req := httptest.NewRequest("GET", "/admin/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
}

func TestAdminMiddlewareAdminTokenOnAdminRoute(t *testing.T) {
	_, userRepo, jwtService := setupTestDBAndServices(t)

	// Create an admin user
	adminUser := createTestUser(t, userRepo, "admin@example.com", true)

	// Generate token for admin user using the same JWT service
	token, err := jwtService.GenerateToken(adminUser.ID, adminUser.Email)
	require.NoError(t, err)

	// Create a test route protected by auth and admin middleware
	app := fiber.New()
	app.Get("/admin/test", middleware.AuthMiddleware(jwtService), middleware.RequireAdmin(userRepo), func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	// Make request with admin token
	req := httptest.NewRequest("GET", "/admin/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}

func TestAuthSchemeCaseInsensitive(t *testing.T) {
	_, userRepo, jwtService := setupTestDBAndServices(t)

	user := createTestUser(t, userRepo, "admin@example.com", true)
	token, err := jwtService.GenerateToken(user.ID, user.Email)
	require.NoError(t, err)

	app := fiber.New()
	app.Get("/protected", middleware.AuthMiddleware(jwtService), func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	// RFC 7235: схема авторизации регистронезависима.
	req := httptest.NewRequest("GET", "/protected", nil)
	req.Header.Set("Authorization", "bearer "+token)
	resp, err := app.Test(req)
	require.NoError(t, err)
	assert.Equal(t, fiber.StatusOK, resp.StatusCode)
}
