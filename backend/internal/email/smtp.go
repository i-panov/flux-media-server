package email

import (
	"crypto/rand"
	"fmt"
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
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
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

	return smtp.SendMail(addr, auth, c.config.Username, []string{to}, []byte(msg))
}
