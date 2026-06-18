package handlers

import (
	"strings"

	"github.com/gofiber/fiber/v2"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/services"
)

type AuthHandler struct {
	userRepo   *repository.UserRepository
	otpStore   *services.OTPStore
	jwtService *services.JWTService
	smtpClient *email.SMTPClient
	config     *config.Config
}

func NewAuthHandler(
	userRepo *repository.UserRepository,
	otpStore *services.OTPStore,
	jwtService *services.JWTService,
	smtpClient *email.SMTPClient,
	config *config.Config,
) *AuthHandler {
	return &AuthHandler{
		userRepo:   userRepo,
		otpStore:   otpStore,
		jwtService: jwtService,
		smtpClient: smtpClient,
		config:     config,
	}
}

type RequestCodeRequest struct {
	Email string `json:"email"`
}

type VerifyCodeRequest struct {
	Email string `json:"email"`
	Code  string `json:"code"`
}

func (h *AuthHandler) RequestCode(c *fiber.Ctx) error {
	var req RequestCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	req.Email = strings.ToLower(req.Email)

	allowed := false
	for _, email := range h.config.Auth.AllowedEmails {
		if strings.ToLower(email) == req.Email {
			allowed = true
			break
		}
	}

	if !allowed && !h.config.Auth.AllowUnknownEmail {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "Email not allowed",
		})
	}

	code := h.otpStore.Generate(req.Email)

	resp := fiber.Map{"message": "Code sent successfully"}

	if h.config.Server.Debug {
		resp["code"] = code
	} else {
		if err := h.smtpClient.SendCode(req.Email, code); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to send code",
			})
		}
	}

	return c.JSON(resp)
}

func (h *AuthHandler) VerifyCode(c *fiber.Ctx) error {
	var req VerifyCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	req.Email = strings.ToLower(req.Email)

	if !h.otpStore.Verify(req.Email, req.Code) {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Invalid or expired code",
		})
	}

	user, err := h.userRepo.FindByEmail(req.Email)
	if err != nil {
		user = &models.User{
			Email: req.Email,
		}
		if err := h.userRepo.Create(user); err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to create user",
			})
		}
	}

	token, err := h.jwtService.GenerateToken(user.ID, user.Email)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "Failed to generate token",
		})
	}

	return c.JSON(fiber.Map{
		"token": token,
		"user": fiber.Map{
			"id":    user.ID,
			"email": user.Email,
		},
	})
}

func (h *AuthHandler) Me(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "Unauthorized",
		})
	}

	user, err := h.userRepo.FindByID(userID)
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "User not found",
		})
	}

	return c.JSON(fiber.Map{
		"id":    user.ID,
		"email": user.Email,
	})
}
