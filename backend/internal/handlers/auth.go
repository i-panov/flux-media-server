package handlers

import (
	"errors"
	"log"
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
		if err := h.smtpClient.SendCode(req.Email, code); err != nil {
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
		if err := h.userRepo.Create(ctx, user); err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Failed to create user")
		}
	}

	tokens, err := h.jwtService.GenerateTokenPair(user.ID, user.Email)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate tokens")
	}

	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	refreshRecord := &models.RefreshToken{
		UserID:    user.ID,
		Token:     tokens.RefreshToken,
		ExpiresAt: time.Now().Add(refreshExpiry),
	}
	if err := h.refreshTokenDB.Create(ctx, refreshRecord); err != nil {
		log.Printf("Failed to store refresh token: %v", err)
	}

	return c.JSON(fiber.Map{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"user": fiber.Map{
			"id":    user.ID,
			"email": user.Email,
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
		"id":    user.ID,
		"email": user.Email,
	})
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

	// Rotate: delete old refresh token, store new one
	_ = h.refreshTokenDB.DeleteByToken(ctx, req.RefreshToken)

	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	refreshRecord := &models.RefreshToken{
		UserID:    user.ID,
		Token:     tokens.RefreshToken,
		ExpiresAt: time.Now().Add(refreshExpiry),
	}
	if err := h.refreshTokenDB.Create(ctx, refreshRecord); err != nil {
		log.Printf("Failed to store refresh token: %v", err)
	}

	return c.JSON(fiber.Map{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}
