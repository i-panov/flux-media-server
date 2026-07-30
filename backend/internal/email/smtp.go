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
	Host       string
	Port       int
	Username   string
	Password   string
	From       string
	RequireTLS bool
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

func (c *SMTPClient) SendCode(to string, code string, expiryMinutes int) error {
	subject := "Flux Media Server - Login Code"
	body := fmt.Sprintf("Your login code is: %s\n\nThis code will expire in %d minutes.", code, expiryMinutes)
	msg := fmt.Sprintf("From: %s\nTo: %s\nSubject: %s\n\n%s", c.config.From, to, subject, body)

	addr := fmt.Sprintf("%s:%d", c.config.Host, c.config.Port)
	auth := smtp.PlainAuth("", c.config.Username, c.config.Password, c.config.Host)

	// Use From address as envelope sender (not Username)
	fromAddr := c.config.From
	if fromAddr == "" {
		fromAddr = c.config.Username
	}

	return sendMailWithTimeout(addr, auth, fromAddr, []string{to}, []byte(msg), c.config.RequireTLS)
}

// sendMailWithTimeout is smtp.SendMail with a connection-level deadline.
func sendMailWithTimeout(addr string, auth smtp.Auth, from string, to []string, msg []byte, requireTLS bool) error {
	conn, err := net.DialTimeout("tcp", addr, smtpTimeout)
	if err != nil {
		return err
	}

	client, err := smtp.NewClient(conn, hostOf(addr))
	if err != nil {
		conn.Close()
		return err
	}
	defer client.Close()

	if err := conn.SetDeadline(time.Now().Add(smtpTimeout)); err != nil {
		return err
	}

	if ok, _ := client.Extension("STARTTLS"); ok {
		tlsConfig := &tls.Config{ServerName: hostOf(addr), MinVersion: tls.VersionTLS12}
		if err := client.StartTLS(tlsConfig); err != nil {
			return err
		}
	} else if requireTLS {
		return fmt.Errorf("smtp: server %s does not support STARTTLS", hostOf(addr))
	}

	if auth != nil {
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
