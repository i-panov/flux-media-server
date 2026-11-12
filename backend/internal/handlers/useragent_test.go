package handlers

import "testing"

func TestDeviceLabelFromUserAgent(t *testing.T) {
	tests := []struct {
		ua       string
		name     string
		platform string
	}{
		{
			"",
			"Браузер",
			"web",
		},
		{
			"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
			"Chrome · Windows",
			"windows",
		},
		{
			"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15",
			"Safari · macOS",
			"macos",
		},
		{
			"Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36",
			"Chrome · Android",
			"android",
		},
		{
			"Mozilla/5.0 (SMART-TV; Linux; Tizen 7.0) AppleWebKit/537.36 SamsungBrowser/5.0",
			"Samsung Internet · Tizen",
			"tizen",
		},
	}
	for _, test := range tests {
		name, platform := deviceLabelFromUserAgent(test.ua)
		if name != test.name || platform != test.platform {
			t.Fatalf("ua %q: got %q/%q, want %q/%q", test.ua, name, platform, test.name, test.platform)
		}
	}
}
