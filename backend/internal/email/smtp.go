package email

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"math/big"
	"net"
	"net/mail"
	"net/smtp"
	"strings"
	"time"
)

// smtpTimeout bounds all SMTP network operations so a hanging server does
// not block a request worker indefinitely.
const smtpTimeout = 15 * time.Second

// randomDigit — источник случайных цифр для GenerateCode. Инициализируется
// один раз вне цикла, чтобы не создавать big.Int на каждую итерацию.
var randomDigit = big.NewInt(10)

type SMTPConfig struct {
	Host        string
	Port        int
	Username    string
	Password    string
	From        string
	RequireTLS  bool
	ImplicitTLS bool
}

type SMTPClient struct {
	config SMTPConfig
}

func NewSMTPClient(config SMTPConfig) *SMTPClient {
	return &SMTPClient{config: config}
}

// GenerateCode generates a numeric code of the given length using
// crypto/rand. It fails on entropy failure — falling back to a predictable
// digit would silently weaken authentication codes.
func GenerateCode(length int) (string, error) {
	if length < 1 {
		return "", fmt.Errorf("code length must be positive, got %d", length)
	}
	var sb strings.Builder
	sb.Grow(length)
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, randomDigit)
		if err != nil {
			return "", fmt.Errorf("crypto/rand unavailable, cannot generate secure code: %w", err)
		}
		fmt.Fprintf(&sb, "%d", n.Int64())
	}
	return sb.String(), nil
}

// validateHeaderValue проверяет значение заголовка письма на CR/LF-инъекции:
// ни одна строка заголовка не должна содержать переводов строки, иначе
// атакующий мог бы вставить дополнительные заголовки в DATA.
func validateHeaderValue(name, value string) error {
	if strings.ContainsAny(value, "\r\n") {
		return fmt.Errorf("smtp: invalid %s header: contains CR/LF", name)
	}
	return nil
}

func (c *SMTPClient) SendCode(to string, code string, expiryMinutes int) error {
	return c.SendCodeContext(context.Background(), to, code, expiryMinutes)
}

// SendCodeContext отправляет письмо с кодом, учитывая отмену контекста.
func (c *SMTPClient) SendCodeContext(ctx context.Context, to string, code string, expiryMinutes int) error {
	subject := "Flux Media Server - Login Code"
	body := fmt.Sprintf("Your login code is: %s\n\nThis code will expire in %d minutes.", code, expiryMinutes)

	// From разбираем через net/mail.ParseAddress: в envelope MAIL FROM
	// подставляется только голый адрес, display-name остаётся в заголовке.
	fromAddr, err := mail.ParseAddress(c.config.From)
	if err != nil {
		return fmt.Errorf("smtp: invalid From address %q: %w", c.config.From, err)
	}

	// To разбираем так же — в envelope RCPT TO идёт голый адрес.
	toAddr, err := mail.ParseAddress(to)
	if err != nil {
		return fmt.Errorf("smtp: invalid To address %q: %w", to, err)
	}

	// Защита от CR/LF-инъекций: значения заголовков проверяются до вставки
	// в DATA. Display-name и адрес могут содержать управляющие символы,
	// поэтому проверяем итоговую строку заголовка.
	fromHeader := fromAddr.String()
	toHeader := toAddr.String()
	if err := validateHeaderValue("From", fromHeader); err != nil {
		return err
	}
	if err := validateHeaderValue("To", toHeader); err != nil {
		return err
	}
	if err := validateHeaderValue("Subject", subject); err != nil {
		return err
	}

	// Полный набор заголовков повышает доставляемость: без Date/Message-ID
	// и MIME-заголовков письмо с большей вероятностью попадает в спам.
	messageID, err := randomMessageID(c.config.Host)
	if err != nil {
		return err
	}
	date := time.Now().Format(time.RFC1123Z)

	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: %s\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n%s",
		fromHeader, toHeader, subject, date, messageID, body)

	addr := fmt.Sprintf("%s:%d", c.config.Host, c.config.Port)

	// Only use authentication if both username and password are set.
	var auth smtp.Auth
	if c.config.Username != "" && c.config.Password != "" {
		auth = smtp.PlainAuth("", c.config.Username, c.config.Password, c.config.Host)
	}

	// MAIL FROM envelope must be a bare address.
	fromEnvelope := fromAddr.Address
	if fromEnvelope == "" {
		fromEnvelope = c.config.Username
	}

	return sendMailWithTimeout(ctx, c.config, addr, auth, fromEnvelope, []string{toAddr.Address}, []byte(msg))
}

// randomMessageID генерирует Message-ID вида <hex@host> для заголовка письма.
func randomMessageID(host string) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("smtp: cannot generate Message-ID: %w", err)
	}
	return fmt.Sprintf("<%x@%s>", b, host), nil
}

// sendMailWithTimeout is smtp.SendMail with a connection-level deadline.
// With ImplicitTLS set (SMTPS, e.g. port 465) TLS is established immediately
// after the TCP connect; otherwise the connection starts in plaintext and is
// upgraded via STARTTLS when the server advertises it.
func sendMailWithTimeout(ctx context.Context, cfg SMTPConfig, addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	dialer := net.Dialer{Timeout: smtpTimeout}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return err
	}
	defer conn.Close()

	// Deadline ставим сразу после установки соединения, ДО smtp.NewClient —
	// он должен покрывать и чтение приветствия, и EHLO.
	if err := conn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
		return err
	}

	host := hostOf(addr)

	if cfg.ImplicitTLS {
		tlsConn := tls.Client(conn, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		// Для ImplicitTLS deadline ставится сразу после установки соединения,
		// чтобы покрыть TLS-рукопожатие.
		if err := tlsConn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
			return err
		}
		if err := tlsConn.Handshake(); err != nil {
			return err
		}
		conn = tlsConn
	}

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}

	tlsActive := cfg.ImplicitTLS
	if !cfg.ImplicitTLS {
		if ok, _ := client.Extension("STARTTLS"); ok {
			tlsConfig := &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}
			if err := client.StartTLS(tlsConfig); err != nil {
				return err
			}
			tlsActive = true
		} else if cfg.RequireTLS {
			return fmt.Errorf("smtp: server %s does not support STARTTLS", host)
		}
	}

	if auth != nil {
		// Никогда не отправляем пароль по незащищённому соединению:
		// PlainAuth передаёт креденшелы по сути открытым текстом.
		if !tlsActive {
			return fmt.Errorf("smtp: refusing to authenticate to %s over a plaintext connection (enable STARTTLS or ImplicitTLS)", host)
		}
		// Timeout the AUTH exchange separately so a slow EHLO+AUTH
		// doesn't block indefinitely.
		if err := conn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
			return err
		}
		if ok, _ := client.Extension("AUTH"); !ok {
			return fmt.Errorf("smtp: server %s does not advertise AUTH although credentials are configured", host)
		}
		if err := client.Auth(auth); err != nil {
			return err
		}
	}

	if err := client.Mail(from); err != nil {
		return err
	}
	for _, rcpt := range to {
		if err := client.Rcpt(rcpt); err != nil {
			return err
		}
	}

	w, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write(msg); err != nil {
		return err
	}
	if err := w.Close(); err != nil {
		return err
	}

	if err := client.Quit(); err != nil {
		// QUIT не удался — явно закрываем соединение, чтобы не оставлять
		// ресурсы на сервере и клиенте.
		client.Close()
		return err
	}
	return nil
}

func hostOf(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}
