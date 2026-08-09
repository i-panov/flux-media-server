package middleware

import (
	"errors"
	"log"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/repository"
	"flux/internal/response"
)

// RequireAdmin allows the request to proceed only if the authenticated user
// has the admin flag. Must be used after AuthMiddleware.
func RequireAdmin(userRepo repository.UserRepository) fiber.Handler {
	return func(c *fiber.Ctx) error {
		userID, ok := c.Locals("user_id").(uint)
		if !ok {
			return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
		}

		user, err := userRepo.FindByID(c.UserContext(), userID)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
			}
			// Database failure — log and return 500 so it is not masked
			// as a simple 401.
			log.Printf("RequireAdmin: FindByID %d: %v", userID, err)
			return response.Error(c, fiber.StatusInternalServerError, "Internal server error")
		}

		if !user.IsAdmin {
			return response.Error(c, fiber.StatusForbidden, "Admin access required")
		}

		return c.Next()
	}
}
