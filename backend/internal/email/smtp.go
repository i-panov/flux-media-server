package email

import (
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"net/smtp"
)

type SMTPConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

type SMTPClient struct {
	config SMTPConfig
}

func NewSMTPClient(config SMTPConfig) *SMTPClient {
	return &SMTPClient{config: config}
}

func GenerateCode(length int) string {
	code := ""
	for i := 0; i < length; i++ {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			log.Printf("Warning: crypto/rand failed, falling back to 0: %v", err)
			code += "0"
			continue
		}
		code += fmt.Sprintf("%d", n.Int64())
	}
	return code
}

func (c *SMTPClient) SendCode(to string, code string) error {
	subject := "Flux Media Server - Login Code"
	body := fmt.Sprintf("Your login code is: %s\n\nThis code will expire in 5 minutes.", code)
	msg := fmt.Sprintf("From: %s\nTo: %s\nSubject: %s\n\n%s", c.config.From, to, subject, body)

	addr := fmt.Sprintf("%s:%d", c.config.Host, c.config.Port)
	auth := smtp.PlainAuth("", c.config.Username, c.config.Password, c.config.Host)

	// Use From address as envelope sender (not Username)
	fromAddr := c.config.From
	if fromAddr == "" {
		fromAddr = c.config.Username
	}

	return smtp.SendMail(addr, auth, fromAddr, []string{to}, []byte(msg))
}
