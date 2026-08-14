package email

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// smtpSession captures the SMTP conversation observed by the test server.
type smtpSession struct {
	mu       sync.Mutex
	mailFrom string
	rcptTo   []string
	authSeen bool
	authCmd  string
	data     strings.Builder
}

func (s *smtpSession) setMailFrom(v string) { s.mu.Lock(); defer s.mu.Unlock(); s.mailFrom = v }
func (s *smtpSession) addRcpt(v string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.rcptTo = append(s.rcptTo, v)
}
func (s *smtpSession) setAuth(v string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.authSeen = true
	s.authCmd = v
}
func (s *smtpSession) addData(v string)    { s.mu.Lock(); defer s.mu.Unlock(); s.data.WriteString(v) }
func (s *smtpSession) getMailFrom() string { s.mu.Lock(); defer s.mu.Unlock(); return s.mailFrom }
func (s *smtpSession) getData() string     { s.mu.Lock(); defer s.mu.Unlock(); return s.data.String() }
func (s *smtpSession) wasAuth() bool       { s.mu.Lock(); defer s.mu.Unlock(); return s.authSeen }

// startSMTPServer поднимает минимальный локальный SMTP-сервер
// (net.Listener + построчные ответы по протоколу SMTP) для тестов.
func startSMTPServer(t *testing.T) (addr string, session *smtpSession) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	session = &smtpSession{}

	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		br := bufio.NewReader(conn)
		bw := bufio.NewWriter(conn)
		write := func(s string) {
			fmt.Fprintf(bw, "%s\r\n", s)
			bw.Flush()
		}
		write("220 test.example ESMTP ready")
		for {
			line, err := br.ReadString('\n')
			if err != nil {
				return
			}
			line = strings.TrimRight(line, "\r\n")
			upper := strings.ToUpper(line)
			switch {
			case strings.HasPrefix(upper, "EHLO"), strings.HasPrefix(upper, "HELO"):
				write("250-test.example")
				write("250-AUTH PLAIN")
				write("250 OK")
			case strings.HasPrefix(upper, "AUTH"):
				session.setAuth(line)
				write("235 2.7.0 Authentication successful")
			case strings.HasPrefix(upper, "MAIL FROM:"):
				session.setMailFrom(strings.TrimSpace(line[len("MAIL FROM:"):]))
				write("250 OK")
			case strings.HasPrefix(upper, "RCPT TO:"):
				session.addRcpt(strings.TrimSpace(line[len("RCPT TO:"):]))
				write("250 OK")
			case upper == "DATA":
				write("354 End data with <CR><LF>.<CR><LF>")
				for {
					l, err := br.ReadString('\n')
					if err != nil {
						return
					}
					if l == ".\r\n" || l == ".\n" {
						break
					}
					session.addData(l)
				}
				write("250 OK: queued")
			case upper == "QUIT":
				write("221 Bye")
				return
			default:
				write("500 unrecognized command")
			}
		}
	}()

	t.Cleanup(func() { ln.Close() })
	return ln.Addr().String(), session
}

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

// TestSendCodeMAILFROMBareAddress проверяет, что в envelope MAIL FROM уходит
// только голый адрес (без display-name), а display-name остаётся в заголовке
// From внутри DATA.
func TestSendCodeMAILFROMBareAddress(t *testing.T) {
	addr, session := startSMTPServer(t)
	host, port, err := net.SplitHostPort(addr)
	require.NoError(t, err)

	client := NewSMTPClient(SMTPConfig{
		Host: host,
		Port: mustPort(t, port),
		From: "Flux Test <sender@example.com>",
	})

	err = client.SendCode("user@example.com", "123456", 5)
	require.NoError(t, err)

	assert.Equal(t, "<sender@example.com>", session.getMailFrom())
	data := session.getData()
	assert.Contains(t, data, "From: \"Flux Test\" <sender@example.com>\r\n")
	assert.Contains(t, data, "To: <user@example.com>\r\n")
	assert.NotContains(t, data, "Bcc:")
}

// TestSendCodeHeaderInjectionRejected проверяет, что попытка CRLF-инъекции
// в адресе получателя отклоняется ещё до соединения с сервером.
func TestSendCodeHeaderInjectionRejected(t *testing.T) {
	client := NewSMTPClient(SMTPConfig{
		Host: "127.0.0.1",
		Port: 25,
		From: "Flux <sender@example.com>",
	})

	// CRLF в адресе получателя — попытка добавить скрытый заголовок Bcc.
	err := client.SendCode("victim@example.com\r\nBcc: hacker@evil.com", "123456", 5)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "invalid To address")
}

// TestSendCodeFromHeaderInjectionRejected — инъекция через display-name From.
func TestSendCodeFromHeaderInjectionRejected(t *testing.T) {
	client := NewSMTPClient(SMTPConfig{
		Host: "127.0.0.1",
		Port: 25,
		From: "Flux\r\nBcc: hacker@evil.com <sender@example.com>",
	})

	err := client.SendCode("user@example.com", "123456", 5)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "invalid From address")
}

// TestSendCodeWithAuth проверяет AUTH-режим: сервер объявляет AUTH PLAIN
// и отвечает 235, письмо успешно доставляется.
func TestSendCodeWithAuth(t *testing.T) {
	addr, session := startSMTPServer(t)
	host, port, err := net.SplitHostPort(addr)
	require.NoError(t, err)

	client := NewSMTPClient(SMTPConfig{
		Host:     host,
		Port:     mustPort(t, port),
		Username: "smtpuser",
		Password: "smtppass",
		From:     "Flux <sender@example.com>",
	})

	err = client.SendCode("user@example.com", "123456", 5)
	require.NoError(t, err)
	assert.True(t, session.wasAuth(), "AUTH command must be sent when credentials are set")
	assert.Contains(t, session.getData(), "Your login code is: 123456")
}

// TestSendCodeNoAuthWithoutCredentials — без креденшелов AUTH не шлётся.
func TestSendCodeNoAuthWithoutCredentials(t *testing.T) {
	addr, session := startSMTPServer(t)
	host, port, err := net.SplitHostPort(addr)
	require.NoError(t, err)

	client := NewSMTPClient(SMTPConfig{
		Host: host,
		Port: mustPort(t, port),
		From: "Flux <sender@example.com>",
	})

	err = client.SendCode("user@example.com", "123456", 5)
	require.NoError(t, err)
	assert.False(t, session.wasAuth(), "AUTH must not be sent without credentials")
}

func mustPort(t *testing.T, port string) int {
	t.Helper()
	var p int
	_, err := fmt.Sscanf(port, "%d", &p)
	require.NoError(t, err)
	return p
}
