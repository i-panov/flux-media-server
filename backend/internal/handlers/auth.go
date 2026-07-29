package handlers

import (
	"errors"
	"log"
	"net/mail"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type AuthHandler struct {
	userRepo       repository.UserRepository
	refreshTokenDB *repository.RefreshTokenRepository
	otpStore       services.OTPStoreInterface
	jwtService     services.JWTService
	smtpClient     *email.SMTPClient
	config         *config.Config
}

func NewAuthHandler(
	userRepo repository.UserRepository,
	refreshTokenRepo *repository.RefreshTokenRepository,
	otpStore services.OTPStoreInterface,
	jwtService services.JWTService,
	smtpClient *email.SMTPClient,
	config *config.Config,
) *AuthHandler {
	return &AuthHandler{
		userRepo:       userRepo,
		refreshTokenDB: refreshTokenRepo,
		otpStore:       otpStore,
		jwtService:     jwtService,
		smtpClient:     smtpClient,
		config:         config,
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
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" {
		return response.Error(c, fiber.StatusBadRequest, "Email is required")
	}

	// Validate the email format. Besides rejecting garbage input, this
	// prevents SMTP header injection through control characters.
	if _, err := mail.ParseAddress(req.Email); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid email address")
	}

	allowed := false
	for _, e := range h.config.Auth.AllowedEmails {
		if strings.ToLower(e) == req.Email {
			allowed = true
			break
		}
	}

	if !allowed && !h.config.Auth.AllowUnknownEmail {
		return response.Error(c, fiber.StatusForbidden, "Email not allowed")
	}

	code, err := h.otpStore.Generate(req.Email)
	if err != nil {
		if errors.Is(err, services.ErrOTPStoreFull) {
			return response.Error(c, fiber.StatusTooManyRequests, "Too many pending codes, please try again later")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate code")
	}

	if h.config.Server.Debug {
		log.Printf("[DEBUG] email=%s, code=%s", req.Email, code)
	}

	resp := fiber.Map{"message": "Code sent successfully"}

	if h.config.Server.Debug {
		resp["code"] = code
	} else {
		expiryMinutes := h.config.Auth.CodeExpiry / 60
		if expiryMinutes < 1 {
			expiryMinutes = 1
		}
		if err := h.smtpClient.SendCode(req.Email, code, expiryMinutes); err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Failed to send code")
		}
	}

	return c.JSON(resp)
}

func (h *AuthHandler) VerifyCode(c *fiber.Ctx) error {
	var req VerifyCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	req.Email = strings.ToLower(strings.TrimSpace(req.Email))

	if !h.otpStore.Verify(req.Email, req.Code) {
		return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired code")
	}

	ctx := c.UserContext()
	user, err := h.userRepo.FindByEmail(ctx, req.Email)
	if err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			log.Printf("FindByEmail error: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Internal server error")
		}
		user = &models.User{
			Email: req.Email,
		}
		// The very first user becomes the administrator.
		if count, cntErr := h.userRepo.Count(ctx); cntErr == nil && count == 0 {
			user.IsAdmin = true
		}
		if err := h.userRepo.Create(ctx, user); err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Failed to create user")
		}
	}

	tokens, err := h.jwtService.GenerateTokenPair(user.ID, user.Email)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate tokens")
	}

	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	if err := h.refreshTokenDB.Create(ctx, user.ID, tokens.RefreshToken, time.Now().Add(refreshExpiry)); err != nil {
		log.Printf("Failed to store refresh token: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create session")
	}

	return c.JSON(fiber.Map{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"user": fiber.Map{
			"id":       user.ID,
			"email":    user.Email,
			"is_admin": user.IsAdmin,
		},
	})
}

func (h *AuthHandler) Me(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	ctx := c.UserContext()
	user, err := h.userRepo.FindByID(ctx, userID)
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "User not found")
	}

	return c.JSON(fiber.Map{
		"id":       user.ID,
		"email":    user.Email,
		"is_admin": user.IsAdmin,
	})
}

// Logout revokes all refresh tokens of the current user (invalidates sessions).
func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	userID, ok := c.Locals("user_id").(uint)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	if err := h.refreshTokenDB.DeleteByUserID(c.UserContext(), userID); err != nil {
		log.Printf("Logout: delete refresh tokens: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
	}

	return c.JSON(fiber.Map{"message": "Logged out successfully"})
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Refresh(c *fiber.Ctx) error {
	var req RefreshRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}

	if req.RefreshToken == "" {
		return response.Error(c, fiber.StatusBadRequest, "Refresh token is required")
	}

	claims, err := h.jwtService.ValidateRefreshToken(req.RefreshToken)
	if err != nil {
		return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired refresh token")
	}

	ctx := c.UserContext()

	// Verify the refresh token exists in the database
	_, err = h.refreshTokenDB.FindByToken(ctx, req.RefreshToken)
	if err != nil {
		return response.Error(c, fiber.StatusUnauthorized, "Invalid refresh token")
	}

	user, err := h.userRepo.FindByID(ctx, claims.UserID)
	if err != nil {
		return response.Error(c, fiber.StatusNotFound, "User not found")
	}

	tokens, err := h.jwtService.GenerateTokenPair(user.ID, user.Email)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate tokens")
	}

	// Rotate: delete old refresh token, store new one. If rotation fails we
	// must not issue the new pair — otherwise multiple valid refresh tokens
	// accumulate silently.
	if err := h.refreshTokenDB.DeleteByToken(ctx, req.RefreshToken); err != nil {
		log.Printf("Failed to rotate refresh token: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to rotate session")
	}

	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	if err := h.refreshTokenDB.Create(ctx, user.ID, tokens.RefreshToken, time.Now().Add(refreshExpiry)); err != nil {
		log.Printf("Failed to store refresh token: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create session")
	}

	return c.JSON(fiber.Map{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}
