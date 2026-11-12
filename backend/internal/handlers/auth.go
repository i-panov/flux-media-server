package handlers

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"log"
	"net/mail"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"gorm.io/gorm"

	"flux/internal/config"
	"flux/internal/email"
	"flux/internal/middleware"
	"flux/internal/models"
	"flux/internal/repository"
	"flux/internal/response"
	"flux/internal/services"
)

type AuthHandler struct {
	userRepo       repository.UserRepository
	refreshTokenDB repository.RefreshTokenRepository
	deviceAuthRepo repository.DeviceAuthRepository
	otpStore       services.OTPStoreInterface
	jwtService     services.JWTService
	smtpClient     *email.SMTPClient
	config         *config.Config
}

func NewAuthHandler(
	userRepo repository.UserRepository,
	refreshTokenRepo repository.RefreshTokenRepository,
	deviceAuthRepo repository.DeviceAuthRepository,
	otpStore services.OTPStoreInterface,
	jwtService services.JWTService,
	smtpClient *email.SMTPClient,
	config *config.Config,
) *AuthHandler {
	return &AuthHandler{
		userRepo:       userRepo,
		refreshTokenDB: refreshTokenRepo,
		deviceAuthRepo: deviceAuthRepo,
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
	Email      string `json:"email"`
	Code       string `json:"code"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
	Platform   string `json:"platform"`
}

// checkSameOrigin защищает эндпоинты, выставляющие сессионные куки,
// от login CSRF: SameSite=Lax не мешает кросс-сайтовому ответу положить
// куки в браузер жертвы, он лишь не отправляет куки в кросс-сайтовых
// запросах. Поэтому запрос с Origin/Referer чужого хоста отклоняется,
// а клиенты без этих заголовков (нативные приложения, curl) пропускаются.
// Сравнение идёт с Host запроса: предполагается прямое подключение без
// переписывающего Host прокси (поддержки прокси в сервере пока нет);
// при её появлении проверку нужно пересмотреть.
func checkSameOrigin(c *fiber.Ctx) bool {
	if origin := c.Get("Origin"); origin != "" {
		u, err := url.Parse(origin)
		if err != nil || u.Host == "" || !strings.EqualFold(u.Host, c.Get(fiber.HeaderHost)) {
			return false
		}
		return true
	}
	if referer := c.Get("Referer"); referer != "" {
		u, err := url.Parse(referer)
		if err != nil || u.Host == "" || !strings.EqualFold(u.Host, c.Get(fiber.HeaderHost)) {
			return false
		}
	}
	return true
}

// setSessionCookies сохраняет пару токенов в httpOnly-куки для веб-клиента.
// JSON с токенами отдаётся как раньше — мобильные клиенты ходят по Bearer.
// SameSite=Lax не даёт чужому сайту отправлять эти куки, но не мешает
// кросс-сайтовому ответу их выставить — от login CSRF verify-code прикрыт
// проверкой Origin/Referer в checkSameOrigin.
func (h *AuthHandler) setSessionCookies(c *fiber.Ctx, accessToken, refreshToken string) {
	secure := h.config.Server.CookieSecure
	c.Cookie(&fiber.Cookie{
		Name:     middleware.CookieAccessToken,
		Value:    accessToken,
		Path:     "/",
		MaxAge:   h.config.Auth.JWTExpiry * 3600,
		HTTPOnly: true,
		Secure:   secure,
		SameSite: fiber.CookieSameSiteLaxMode,
	})
	c.Cookie(&fiber.Cookie{
		Name:     middleware.CookieRefreshToken,
		Value:    refreshToken,
		Path:     "/api/auth",
		MaxAge:   h.config.Auth.RefreshExpiry * 3600,
		HTTPOnly: true,
		Secure:   secure,
		SameSite: fiber.CookieSameSiteLaxMode,
	})
}

// clearSessionCookies гасит обе сессионные куки. Истёкшее значение ставится
// с тем же Path, что при установке (у refresh-куки — /api/auth),
// иначе браузер проигнорирует удаление.
func (h *AuthHandler) clearSessionCookies(c *fiber.Ctx) {
	secure := h.config.Server.CookieSecure
	paths := map[string]string{
		middleware.CookieAccessToken:  "/",
		middleware.CookieRefreshToken: "/api/auth",
	}
	for name, path := range paths {
		c.Cookie(&fiber.Cookie{
			Name:     name,
			Value:    "",
			Path:     path,
			MaxAge:   -1,
			Expires:  time.Unix(0, 0).UTC(),
			HTTPOnly: true,
			Secure:   secure,
			SameSite: fiber.CookieSameSiteLaxMode,
		})
	}
}

const userCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func randomUserCode() (string, error) {
	raw := make([]byte, 8)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	out := make([]byte, len(raw))
	for i, b := range raw {
		out[i] = userCodeAlphabet[int(b)%len(userCodeAlphabet)]
	}
	return string(out), nil
}

func randomDeviceCode() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func normalizeDeviceLabel(name, platform string) (string, string) {
	name = strings.TrimSpace(name)
	platform = strings.ToLower(strings.TrimSpace(platform))
	if len(name) > 120 {
		name = name[:120]
	}
	if len(platform) > 32 {
		platform = platform[:32]
	}
	if name == "" {
		switch platform {
		case "androidtv", "tv":
			name = "Android TV"
		case "ios":
			name = "iPhone / iPad"
		case "android":
			name = "Android"
		default:
			name = "Устройство"
		}
	}
	if platform == "" {
		platform = "unknown"
	}
	return name, platform
}

func (h *AuthHandler) issueSession(c *fiber.Ctx, user *models.User, deviceID, name, platform string) (map[string]any, error) {
	ctx := c.UserContext()
	tokens, err := h.jwtService.GenerateTokenPair(user.ID, user.Email)
	if err != nil {
		return nil, err
	}
	if deviceID == "" {
		deviceID, err = randomDeviceCode()
		if err != nil {
			return nil, err
		}
	}
	name = h.uniqueDeviceName(ctx, user.ID, deviceID, name)
	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	if err := h.refreshTokenDB.CreateSession(ctx, user.ID, tokens.RefreshToken, time.Now().Add(refreshExpiry), repository.SessionMeta{
		DeviceID:   deviceID,
		DeviceName: name,
		Platform:   platform,
	}); err != nil {
		return nil, err
	}
	h.setSessionCookies(c, tokens.AccessToken, tokens.RefreshToken)
	return map[string]any{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"user": fiber.Map{
			"id":       user.ID,
			"email":    user.Email,
			"is_admin": user.IsAdmin,
		},
	}, nil
}

func (h *AuthHandler) deviceLabelForRequest(c *fiber.Ctx, name, platform string) (string, string) {
	if strings.TrimSpace(name) == "" || strings.TrimSpace(platform) == "" {
		uaName, uaPlatform := deviceLabelFromUserAgent(c.Get("User-Agent"))
		if strings.TrimSpace(name) == "" {
			name = uaName
		}
		if strings.TrimSpace(platform) == "" {
			platform = uaPlatform
		}
	}
	return normalizeDeviceLabel(name, platform)
}

// uniqueDeviceName не даёт двум устройствам одного пользователя
// называться одинаково: иначе список сессий снова превращается в кашу.
func (h *AuthHandler) uniqueDeviceName(ctx context.Context, userID uint, deviceID, requested string) string {
	name := strings.TrimSpace(requested)
	if name == "" {
		name = "Устройство"
	}
	tokens, err := h.refreshTokenDB.ListByUserID(ctx, userID)
	if err != nil {
		return name
	}
	used := make(map[string]struct{}, len(tokens))
	for _, token := range tokens {
		if token.DeviceID == "" || token.DeviceID == deviceID {
			continue
		}
		used[strings.ToLower(token.DeviceName)] = struct{}{}
	}
	base := name
	for i := 2; ; i++ {
		if _, taken := used[strings.ToLower(name)]; !taken {
			return name
		}
		name = fmt.Sprintf("%s (%d)", base, i)
	}
}

func (h *AuthHandler) verificationBaseURL(c *fiber.Ctx) string {
	if h.config.Server.PublicURL != "" {
		return h.config.Server.PublicURL
	}
	scheme := c.Protocol()
	host := c.Get("Host")
	return fmt.Sprintf("%s://%s", scheme, host)
}

type DeviceCodeRequest struct {
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
	Platform   string `json:"platform"`
}

// DeviceCode создаёт одноразовый код для входа на ТВ/приставке. Сырые
// коды возвращаются только здесь; в БД лежат хеши.
func (h *AuthHandler) DeviceCode(c *fiber.Ctx) error {
	var req DeviceCodeRequest
	if err := c.BodyParser(&req); err != nil && len(c.Body()) > 0 {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	name, platform := normalizeDeviceLabel(req.DeviceName, req.Platform)
	deviceCode, err := randomDeviceCode()
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate device code")
	}
	userCode, err := randomUserCode()
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate user code")
	}
	expiresIn := h.config.Auth.CodeExpiry
	if expiresIn < 120 {
		expiresIn = 120
	}
	deviceID := strings.TrimSpace(req.DeviceID)
	if deviceID == "" {
		deviceID, err = randomDeviceCode()
		if err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Failed to generate device id")
		}
	}
	interval := 3
	// Ленивая уборка: отдельный воркер для короткоживущих кодов избыточен.
	_ = h.deviceAuthRepo.DeleteExpired(c.UserContext())
	_, err = h.deviceAuthRepo.Create(
		c.UserContext(),
		repository.HashDeviceCode(deviceCode),
		repository.HashDeviceCode(userCode),
		deviceID,
		name,
		platform,
		time.Now().Add(time.Duration(expiresIn)*time.Second),
		interval,
	)
	if err != nil {
		log.Printf("device code: create: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create device code")
	}
	base := h.verificationBaseURL(c)
	verification := base + "/activate"
	return c.JSON(fiber.Map{
		"device_code":               deviceCode,
		"user_code":                 userCode,
		"verification_uri":          verification,
		"verification_uri_complete": verification + "?code=" + url.QueryEscape(userCode),
		"expires_in":                expiresIn,
		"interval":                  interval,
	})
}

type DeviceUserCodeRequest struct {
	UserCode string `json:"user_code"`
}

func (h *AuthHandler) InspectDevice(c *fiber.Ctx) error {
	if _, ok := middleware.GetUserID(c); !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	var req DeviceUserCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	code := strings.ToUpper(strings.TrimSpace(req.UserCode))
	if code == "" {
		return response.Error(c, fiber.StatusBadRequest, "user_code is required")
	}
	record, err := h.deviceAuthRepo.FindPendingByUserCode(c.UserContext(), repository.HashDeviceCode(code))
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Code not found or already used")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to inspect code")
	}
	if time.Now().After(record.ExpiresAt) {
		return response.Error(c, fiber.StatusGone, "Code expired")
	}
	return c.JSON(fiber.Map{
		"device_name": record.DeviceName,
		"platform":    record.Platform,
		"expires_at":  record.ExpiresAt,
	})
}

func (h *AuthHandler) ApproveDevice(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	var req DeviceUserCodeRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	code := strings.ToUpper(strings.TrimSpace(req.UserCode))
	if code == "" {
		return response.Error(c, fiber.StatusBadRequest, "user_code is required")
	}
	record, err := h.deviceAuthRepo.Approve(c.UserContext(), repository.HashDeviceCode(code), userID)
	if err != nil {
		if errors.Is(err, repository.ErrDeviceCodeInvalid) {
			return response.Error(c, fiber.StatusNotFound, "Code not found, expired or already used")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to approve device")
	}
	return c.JSON(fiber.Map{
		"approved":    true,
		"device_name": record.DeviceName,
		"platform":    record.Platform,
	})
}

type DeviceTokenRequest struct {
	DeviceCode string `json:"device_code"`
}

func (h *AuthHandler) DeviceToken(c *fiber.Ctx) error {
	if !checkSameOrigin(c) {
		return response.Error(c, fiber.StatusForbidden, "Cross-origin request rejected")
	}
	var req DeviceTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	if req.DeviceCode == "" {
		return response.Error(c, fiber.StatusBadRequest, "device_code is required")
	}
	ctx := c.UserContext()
	record, err := h.deviceAuthRepo.FindByDeviceCode(ctx, repository.HashDeviceCode(req.DeviceCode))
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return reaction(c, fiber.StatusBadRequest, "invalid_grant")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to poll device code")
	}
	if time.Now().After(record.ExpiresAt) && record.Status != models.DeviceAuthConsumed {
		return reaction(c, fiber.StatusOK, "expired")
	}
	switch record.Status {
	case models.DeviceAuthPending:
		return c.JSON(fiber.Map{"status": "pending", "interval": record.IntervalSeconds})
	case models.DeviceAuthApproved:
		consumed, err := h.deviceAuthRepo.Consume(ctx, record.DeviceCodeHash)
		if err != nil {
			return reaction(c, fiber.StatusOK, "expired")
		}
		if consumed.UserID == nil {
			return reaction(c, fiber.StatusBadRequest, "invalid_grant")
		}
		user, err := h.userRepo.FindByID(ctx, *consumed.UserID)
		if err != nil {
			return reaction(c, fiber.StatusBadRequest, "invalid_grant")
		}
		payload, err := h.issueSession(c, user, consumed.DeviceID, consumed.DeviceName, consumed.Platform)
		if err != nil {
			log.Printf("device token: issue session: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to create session")
		}
		payload["status"] = "ok"
		return c.JSON(payload)
	default:
		return reaction(c, fiber.StatusOK, "expired")
	}
}

func reaction(c *fiber.Ctx, status int, code string) error {
	return c.Status(status).JSON(fiber.Map{"status": code})
}

func (h *AuthHandler) ListDevices(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	tokens, err := h.refreshTokenDB.ListByUserID(c.UserContext(), userID)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to load devices")
	}
	currentID := strings.TrimSpace(c.Query("device_id"))
	type summary struct {
		DeviceID   string
		Name       string
		Platform   string
		CreatedAt  time.Time
		LastUsedAt *time.Time
		ExpiresAt  time.Time
	}
	devices := make(map[string]*summary)
	for _, token := range tokens {
		deviceID := token.DeviceID
		if deviceID == "" {
			// Старые сессии без device_id показываем отдельными записями.
			deviceID = fmt.Sprintf("legacy-%d", token.ID)
		}
		item, exists := devices[deviceID]
		if !exists {
			name := token.DeviceName
			if name == "" || strings.EqualFold(name, "Устройство") {
				name = "Браузер"
			}
			devices[deviceID] = &summary{
				DeviceID:   deviceID,
				Name:       name,
				Platform:   token.Platform,
				CreatedAt:  token.CreatedAt,
				LastUsedAt: token.LastUsedAt,
				ExpiresAt:  token.ExpiresAt,
			}
			continue
		}
		if token.DeviceName != "" {
			item.Name = token.DeviceName
		}
		if token.Platform != "" {
			item.Platform = token.Platform
		}
		if token.CreatedAt.Before(item.CreatedAt) {
			item.CreatedAt = token.CreatedAt
		}
		if token.LastUsedAt != nil && (item.LastUsedAt == nil || token.LastUsedAt.After(*item.LastUsedAt)) {
			item.LastUsedAt = token.LastUsedAt
		}
		if token.ExpiresAt.After(item.ExpiresAt) {
			item.ExpiresAt = token.ExpiresAt
		}
	}
	items := make([]fiber.Map, 0, len(devices))
	for _, item := range devices {
		items = append(items, fiber.Map{
			"device_id":    item.DeviceID,
			"device_name":  item.Name,
			"platform":     item.Platform,
			"created_at":   item.CreatedAt,
			"last_used_at": item.LastUsedAt,
			"expires_at":   item.ExpiresAt,
			"current":      currentID != "" && item.DeviceID == currentID,
		})
	}
	sort.Slice(items, func(i, j int) bool {
		left, _ := items[i]["created_at"].(time.Time)
		right, _ := items[j]["created_at"].(time.Time)
		return left.After(right)
	})
	return c.JSON(fiber.Map{"items": items})
}

func (h *AuthHandler) RevokeDevice(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	deviceID := strings.TrimSpace(c.Params("device_id"))
	if deviceID == "" {
		return response.Error(c, fiber.StatusBadRequest, "Invalid device id")
	}
	if err := h.refreshTokenDB.DeleteByDeviceID(c.UserContext(), deviceID, userID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Device not found")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to revoke device")
	}
	return c.JSON(fiber.Map{"message": "Device revoked"})
}

func (h *AuthHandler) RenameDevice(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}
	deviceID := strings.TrimSpace(c.Params("device_id"))
	if deviceID == "" {
		return response.Error(c, fiber.StatusBadRequest, "Invalid device id")
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := c.BodyParser(&req); err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || len([]rune(name)) > 80 {
		return response.Error(c, fiber.StatusBadRequest, "Device name must be 1..80 characters")
	}
	tokens, err := h.refreshTokenDB.ListByUserID(c.UserContext(), userID)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to load devices")
	}
	for _, token := range tokens {
		if token.DeviceID != deviceID && strings.EqualFold(strings.TrimSpace(token.DeviceName), name) {
			return response.Error(c, fiber.StatusConflict, "Device name is already used")
		}
	}
	if err := h.refreshTokenDB.RenameDevice(c.UserContext(), userID, deviceID, name); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusNotFound, "Device not found")
		}
		return response.Error(c, fiber.StatusInternalServerError, "Failed to rename device")
	}
	return c.JSON(fiber.Map{"message": "Device renamed", "device_name": name})
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
	// Парсинг отбрасывает display-name: allowlist сравнивается по голому
	// адресу, иначе "User <user@example.com>" не совпал бы со списком.
	addr, err := mail.ParseAddress(req.Email)
	if err != nil {
		return response.Error(c, fiber.StatusBadRequest, "Invalid email address")
	}
	req.Email = strings.ToLower(addr.Address)

	allowed := false
	for _, e := range h.config.Auth.AllowedEmails {
		if strings.ToLower(e) == req.Email {
			allowed = true
			break
		}
	}

	if !allowed && !h.config.Auth.AllowUnknownEmail {
		// Не раскрываем существование email в allowlist (user enumeration):
		// отвечаем как при успешной отправке, не генерируя код и не
		// отправляя письмо.
		return c.JSON(fiber.Map{"message": "Code sent successfully"})
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
		if err := h.smtpClient.SendCodeContext(c.UserContext(), req.Email, code, expiryMinutes); err != nil {
			// Письмо не ушло — удаляем сгенерированный код из стора, чтобы
			// не оставлять рабочий OTP без уведомления пользователя.
			h.otpStore.Remove(req.Email)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to send code")
		}
	}

	return c.JSON(resp)
}

func (h *AuthHandler) VerifyCode(c *fiber.Ctx) error {
	// Первой — до разбора тела и проверки кода: кросс-сайтовый запрос
	// не должен ни тратить чужой OTP, ни получать сессионные куки.
	if !checkSameOrigin(c) {
		return response.Error(c, fiber.StatusForbidden, "Cross-origin request rejected")
	}

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
		// Create handles the TOCTOU-safe first-user-admin promotion internally.
		if err := h.userRepo.Create(ctx, user); err != nil {
			return response.Error(c, fiber.StatusInternalServerError, "Failed to create user")
		}
	}

	name, platform := h.deviceLabelForRequest(c, req.DeviceName, req.Platform)
	payload, err := h.issueSession(c, user, req.DeviceID, name, platform)
	if err != nil {
		log.Printf("Failed to create session: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to create session")
	}
	return c.JSON(payload)
}

func (h *AuthHandler) Me(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
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

// Logout revokes refresh tokens. If refresh_token_id is provided only that
// specific token is revoked; otherwise all tokens of the current user are
// deleted (full logout). Тело опционально: невалидный JSON приравнивается
// к отсутствующему телу — полный logout безопаснее, чем ошибка 400.
func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	userID, ok := middleware.GetUserID(c)
	if !ok {
		return response.Error(c, fiber.StatusUnauthorized, "Unauthorized")
	}

	var req struct {
		RefreshToken   string `json:"refresh_token"`
		RefreshTokenID *uint  `json:"refresh_token_id"`
	}
	if err := c.BodyParser(&req); err != nil {
		log.Printf("Logout: invalid body, falling back to session logout: %v", err)
	}

	ctx := c.UserContext()
	refreshToken := strings.TrimSpace(req.RefreshToken)
	if refreshToken == "" {
		refreshToken = c.Cookies(middleware.CookieRefreshToken)
	}
	if req.RefreshTokenID != nil {
		if err := h.refreshTokenDB.DeleteByID(ctx, *req.RefreshTokenID, userID); err != nil {
			log.Printf("Logout: delete refresh token %d: %v", *req.RefreshTokenID, err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
		}
	} else if refreshToken != "" {
		// Выход с устройства удаляет только его сессии, а не все
		// устройства пользователя.
		record, err := h.refreshTokenDB.FindByToken(ctx, refreshToken)
		if err == nil && record.UserID == userID {
			if record.DeviceID == "" {
				if err := h.refreshTokenDB.DeleteByToken(ctx, refreshToken); err != nil {
					log.Printf("Logout: delete refresh token: %v", err)
					return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
				}
			} else if err := h.refreshTokenDB.DeleteByDeviceID(ctx, record.DeviceID, userID); err != nil {
				log.Printf("Logout: delete device: %v", err)
				return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
			}
		} else if err := h.refreshTokenDB.DeleteByToken(ctx, refreshToken); err != nil {
			log.Printf("Logout: delete refresh token: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
		}
	} else {
		if err := h.refreshTokenDB.DeleteByUserID(ctx, userID); err != nil {
			log.Printf("Logout: delete refresh tokens: %v", err)
			return response.Error(c, fiber.StatusInternalServerError, "Failed to logout")
		}
	}

	h.clearSessionCookies(c)

	return c.JSON(fiber.Map{"message": "Logged out successfully"})
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (h *AuthHandler) Refresh(c *fiber.Ctx) error {
	// Как и verify-code, выставляет сессионные куки на публичном роуте —
	// без проверки это второй вход для login CSRF.
	if !checkSameOrigin(c) {
		return response.Error(c, fiber.StatusForbidden, "Cross-origin request rejected")
	}

	// Веб-клиент присылает refresh-токен в httpOnly-куке и может вообще
	// не слать тело — куку читаем до разбора тела, иначе запрос без тела
	// упрётся в ошибку BodyParser и до куки дело не дойдёт.
	refreshToken := c.Cookies(middleware.CookieRefreshToken)
	if refreshToken == "" {
		var req RefreshRequest
		if err := c.BodyParser(&req); err != nil {
			return response.Error(c, fiber.StatusBadRequest, "Invalid request body")
		}
		refreshToken = req.RefreshToken
	}
	if refreshToken == "" {
		return response.Error(c, fiber.StatusBadRequest, "Refresh token is required")
	}

	claims, err := h.jwtService.ValidateRefreshToken(refreshToken)
	if err != nil {
		return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired refresh token")
	}

	ctx := c.UserContext()

	user, err := h.userRepo.FindByID(ctx, claims.UserID)
	if err != nil {
		return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired refresh token")
	}

	tokens, err := h.jwtService.GenerateTokenPair(user.ID, user.Email)
	if err != nil {
		return response.Error(c, fiber.StatusInternalServerError, "Failed to generate tokens")
	}

	// Rotate atomically: delete old refresh token, store new one in a single
	// transaction. If rotation fails we must not issue the new pair —
	// otherwise multiple valid refresh tokens accumulate silently.
	// RotateToken возвращает сохранённый новый токен; в ответ отдаём
	// только что сгенерированный из GenerateTokenPair.
	refreshExpiry := time.Duration(h.config.Auth.RefreshExpiry) * time.Hour
	if _, err := h.refreshTokenDB.RotateToken(ctx, refreshToken, user.ID, tokens.RefreshToken, time.Now().Add(refreshExpiry)); err != nil {
		// A missing row means the token was already rotated (replay) or
		// revoked — treat it as an auth failure, not a server error.
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return response.Error(c, fiber.StatusUnauthorized, "Invalid or expired refresh token")
		}
		log.Printf("Failed to rotate refresh token: %v", err)
		return response.Error(c, fiber.StatusInternalServerError, "Failed to rotate session")
	}

	h.setSessionCookies(c, tokens.AccessToken, tokens.RefreshToken)

	return c.JSON(fiber.Map{
		"token":         tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}
