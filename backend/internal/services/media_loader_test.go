package services

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"flux/internal/models"
)

type fakeLoaderQueue struct {
	mu       sync.Mutex
	enqueued []UploadJobInput
	status   UploadJobStatus
}

func (f *fakeLoaderQueue) Enqueue(in UploadJobInput) (uint64, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.enqueued = append(f.enqueued, in)
	return 42, nil
}

func (f *fakeLoaderQueue) Cancel(uint64) error { return nil }

func (f *fakeLoaderQueue) Status(uint64) (UploadJobStatus, bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.status, true
}

func TestMediaLoaderImportsFileAndEnqueues(t *testing.T) {
	var polls int
	mux := http.NewServeMux()
	mux.HandleFunc("/videos", func(w http.ResponseWriter, r *http.Request) {
		polls++
		if polls == 1 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusAccepted)
			_, _ = w.Write([]byte(`{"status":"downloading","stage":"downloading","retry_after":0,"progress":{"percent":12.5}}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"download_url":"/downloads/token","filename":"Video.mp4","content_type":"video/mp4","title":"Video"}`))
	})
	mux.HandleFunc("/downloads/token", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "video/mp4")
		_, _ = w.Write([]byte("video-bytes"))
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	queue := &fakeLoaderQueue{status: UploadJobStatus{Status: UploadJobDone, MediaID: 7}}
	dir := t.TempDir()
	loader := NewMediaLoader(srv.URL, "", dir, 1024, 5*time.Second, queue)
	job, err := loader.Submit(MediaLoaderRequest{URL: "https://example.com/video", Format: "mp4"})
	require.NoError(t, err)
	require.Equal(t, "queued", job.Status)

	require.Eventually(t, func() bool {
		got, ok := loader.Get(job.ID)
		return ok && got.Status == "done"
	}, 15*time.Second, 10*time.Millisecond)

	got, ok := loader.Get(job.ID)
	require.True(t, ok)
	require.Equal(t, uint(7), got.MediaID)
	require.Equal(t, uint64(42), got.UploadJobID)

	queue.mu.Lock()
	defer queue.mu.Unlock()
	require.Len(t, queue.enqueued, 1)
	require.Equal(t, models.MediaTypeVideo, queue.enqueued[0].MediaType)
	require.Equal(t, "Video.mp4", queue.enqueued[0].Filename)
	content, err := os.ReadFile(filepath.Join(dir, "Video.mp4"))
	require.NoError(t, err)
	require.Equal(t, "video-bytes", string(content))
}

func TestMediaLoaderRejectsInvalidURL(t *testing.T) {
	loader := NewMediaLoader("http://127.0.0.1:1", "", t.TempDir(), 1024, time.Second, &fakeLoaderQueue{})
	_, err := loader.Submit(MediaLoaderRequest{URL: "file:///etc/passwd"})
	require.Error(t, err)
}

func TestMediaLoaderDisabled(t *testing.T) {
	loader := NewMediaLoader("", "", t.TempDir(), 1024, time.Second, &fakeLoaderQueue{})
	_, err := loader.Submit(MediaLoaderRequest{URL: "https://example.com"})
	require.ErrorIs(t, err, ErrMediaLoaderDisabled)
}

func TestSafeLoaderFilename(t *testing.T) {
	require.Equal(t, "video.mp4", safeLoaderFilename("../../video.mp4"))
	require.Equal(t, "", safeLoaderFilename(".."))
	require.Equal(t, "", safeLoaderFilename(" "))
}

// JSON-контракт статуса не должен случайно начать отдавать внутренние поля.
func TestMediaLoaderJobJSON(t *testing.T) {
	job := MediaLoaderJob{ID: "x", Status: "queued", mediaType: models.MediaTypeVideo}
	data, err := json.Marshal(job)
	require.NoError(t, err)
	require.NotContains(t, string(data), "mediaType")
}
