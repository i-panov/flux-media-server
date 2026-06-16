package email

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGenerateCode(t *testing.T) {
	code := GenerateCode(6)
	assert.Len(t, code, 6)
	assert.Regexp(t, `^\d{6}$`, code)
}

func TestNewSMTPClient(t *testing.T) {
	client := NewSMTPClient(SMTPConfig{
		Host:     "smtp.test.com",
		Port:     587,
		Username: "test@test.com",
		Password: "password",
		From:     "Test <test@test.com>",
	})
	assert.NotNil(t, client)
}
