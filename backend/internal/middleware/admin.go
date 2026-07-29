package middleware

import (
	"github.com/gofiber/fiber/v2"

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
			return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
		}

		if !user.IsAdmin {
			return response.Error(c, fiber.StatusForbidden, "Admin access required")
		}

		return c.Next()
	}
}
