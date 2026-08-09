package services_test

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"flux/internal/models"
	"flux/internal/services"
)

// MockScanner is a mock for the ScannerInterface
type MockScanner struct {
	mock.Mock
	scanCalled chan bool
}

func (m *MockScanner) ScanPath(ctx context.Context, path string, mediaType models.MediaType) error {
	args := m.Called(ctx, path, mediaType)
	return args.Error(0)
}

func (m *MockScanner) ScanAll(ctx context.Context) error {
	m.Called(ctx)

	// Signal that ScanAll was called
	if m.scanCalled != nil {
		select {
		case m.scanCalled <- true:
		default:
		}
	}

	return nil
}

func (m *MockScanner) GetScanStatus(key string) *services.ScanStatus {
	args := m.Called(key)
	return args.Get(0).(*services.ScanStatus)
}

func TestWatcherDebounce(t *testing.T) {
	// This test verifies the debounce functionality (B4 watcher fix)
	// It should trigger exactly one ScanAll after a burst of events

	// Create mock scanner
	mockScanner := &MockScanner{
		scanCalled: make(chan bool, 10), // Buffer to avoid blocking
	}

	// Set up expectations - ScanAll should be called exactly once
	mockScanner.On("ScanAll", mock.Anything).Return(nil)

	// Create watcher service
	watcher := services.NewWatcherService(mockScanner)

	// Create test directory
	tempDir := t.TempDir()

	// Start watching
	err := watcher.StartWithPaths([]string{tempDir})
	require.NoError(t, err)

	// Trigger multiple events rapidly (burst)
	for i := 0; i < 5; i++ {
		testFile := filepath.Join(tempDir, "test"+string(rune('0'+i))+".txt")
		err := os.WriteFile(testFile, []byte("test content"), 0644)
		require.NoError(t, err)

		// Small delay between events (but still within debounce window)
		time.Sleep(10 * time.Millisecond)
	}

	// Wait for debounce to trigger (2 seconds + some margin)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	select {
	case <-mockScanner.scanCalled:
		// ScanAll was called, which is expected
	case <-ctx.Done():
		t.Fatal("ScanAll was not called within expected time")
	}

	// Give some time for the mock expectation to be satisfied
	time.Sleep(100 * time.Millisecond)

	// Stop the watcher
	watcher.Stop()

	// Assert that ScanAll was called exactly once
	mockScanner.AssertNumberOfCalls(t, "ScanAll", 1)
}

func TestWatcherDisabled(t *testing.T) {
	// This test verifies that changes are ignored if watcher is not started

	// Create mock scanner
	mockScanner := &MockScanner{}

	// Create watcher service
	watcher := services.NewWatcherService(mockScanner)

	// Note: NOT starting the watcher with StartWithPaths

	// Create test directory
	tempDir := t.TempDir()

	// Create a file (should be ignored since watcher is not started)
	testFile := filepath.Join(tempDir, "test.txt")
	err := os.WriteFile(testFile, []byte("test content"), 0644)
	require.NoError(t, err)

	// Wait a bit to ensure no scan happens
	time.Sleep(100 * time.Millisecond)

	// Stop the watcher (even though it wasn't started)
	watcher.Stop()

	// Assert that ScanAll was never called
	mockScanner.AssertNotCalled(t, "ScanAll")
}
