package email

import (
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"math/big"
	"net"
	"net/smtp"
	"strings"
	"time"
)

// smtpTimeout bounds all SMTP network operations so a hanging server does
// not block a request worker indefinitely.
const smtpTimeout = 15 * time.Second

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
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			panic(fmt.Sprintf("crypto/rand unavailable, cannot generate secure code: %v", err))
		}
		fmt.Fprintf(&sb, "%d", n.Int64())
	}
	return sb.String(), nil
}

// extractAddress strips display-name from "Name <email>" → "email".
// The SMTP MAIL FROM command must contain only the address.
func extractAddress(addr string) string {
	if i := strings.LastIndex(addr, "<"); i != -1 {
		if j := strings.Index(addr[i:], ">"); j != -1 {
			return addr[i+1 : i+j]
		}
	}
	return addr
}

// Sanitize 'to' to prevent header injection — strip newlines and
// limit length to prevent buffer overflow attacks.
func sanitizeEmail(addr string) string {
	s := strings.Map(func(r rune) rune {
		if r == '\n' || r == '\r' {
			return -1
		}
		return r
	}, addr)
	if len(s) > 254 {
		s = s[:254]
	}
	return strings.TrimSpace(s)
}

func (c *SMTPClient) SendCode(to string, code string, expiryMinutes int) error {
	subject := "Flux Media Server - Login Code"
	body := fmt.Sprintf("Your login code is: %s\n\nThis code will expire in %d minutes.", code, expiryMinutes)
	sanitizedTo := sanitizeEmail(to)
	msg := fmt.Sprintf("From: <%s>\r\nTo: <%s>\r\nSubject: %s\r\n\r\n%s",
		c.config.From, sanitizedTo, subject, body)

	addr := fmt.Sprintf("%s:%d", c.config.Host, c.config.Port)

	// Only use authentication if both username and password are set.
	var auth smtp.Auth
	if c.config.Username != "" && c.config.Password != "" {
		auth = smtp.PlainAuth("", c.config.Username, c.config.Password, c.config.Host)
	}

	// MAIL FROM envelope must be a bare address.
	fromAddr := extractAddress(c.config.From)
	if fromAddr == "" {
		fromAddr = c.config.Username
	}

	return sendMailWithTimeout(c.config, addr, auth, fromAddr, []string{to}, []byte(msg))
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

	host := hostOf(addr)

	if cfg.ImplicitTLS {
		tlsConn := tls.Client(conn, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
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

	if err := conn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
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

	return client.Quit()
}

func hostOf(addr string) string {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return addr
	}
	return host
}
