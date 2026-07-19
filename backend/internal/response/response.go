package response

import "github.com/gofiber/fiber/v2"

// ErrorResponse is the standard error envelope for all API responses.
type ErrorResponse struct {
	Error   string `json:"error"`
	Details string `json:"details,omitempty"`
}

// Error sends a JSON error response with the given status code.
func Error(c *fiber.Ctx, status int, message string) error {
	return c.Status(status).JSON(ErrorResponse{Error: message})
}

// Errorf sends a JSON error response with additional details.
func Errorf(c *fiber.Ctx, status int, message, details string) error {
	return c.Status(status).JSON(ErrorResponse{Error: message, Details: details})
}
