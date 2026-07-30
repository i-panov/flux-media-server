package email

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGenerateCode(t *testing.T) {
	code, err := GenerateCode(6)
	require.NoError(t, err)
	assert.Len(t, code, 6)
	assert.Regexp(t, `^\d{6}$`, code)

	_, err = GenerateCode(0)
	assert.Error(t, err)

	_, err = GenerateCode(-1)
	assert.Error(t, err)
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
