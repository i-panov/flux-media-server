package email

import (
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
// crypto/rand. It panics on entropy failure — falling back to a predictable
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
			panic(fmt.Sprintf("crypto/rand unavailable, cannot generate secure code: %v", err))
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

	msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n%s",
		fromHeader, toHeader, subject, body)

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

	return sendMailWithTimeout(c.config, addr, auth, fromEnvelope, []string{toAddr.Address}, []byte(msg))
}

// sendMailWithTimeout is smtp.SendMail with a connection-level deadline.
// With ImplicitTLS set (SMTPS, e.g. port 465) TLS is established immediately
// after the TCP connect; otherwise the connection starts in plaintext and is
// upgraded via STARTTLS when the server advertises it.
func sendMailWithTimeout(cfg SMTPConfig, addr string, auth smtp.Auth, from string, to []string, msg []byte) error {
	conn, err := net.DialTimeout("tcp", addr, smtpTimeout)
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

	if !cfg.ImplicitTLS {
		if ok, _ := client.Extension("STARTTLS"); ok {
			tlsConfig := &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}
			if err := client.StartTLS(tlsConfig); err != nil {
				return err
			}
		} else if cfg.RequireTLS {
			return fmt.Errorf("smtp: server %s does not support STARTTLS", host)
		}
	}

	if auth != nil {
		// Timeout the AUTH exchange separately so a slow EHLO+AUTH
		// doesn't block indefinitely.
		if err := conn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
			return err
		}
		if ok, _ := client.Extension("AUTH"); ok {
			if err := client.Auth(auth); err != nil {
				return err
			}
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
