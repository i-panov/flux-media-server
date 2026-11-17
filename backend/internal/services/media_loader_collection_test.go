package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestRunCollectionReportsFailedEpisodes(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"status":"ready","collection":true,
			"series":{"id":"s1","title":"Сериал"},
			"episodes":[
				{"season":1,"episode":1,"title":"Готовая","status":"ready","download_url":"/downloads/a","filename":"a.mp4"},
				{"season":1,"episode":2,"title":"Битая","status":"failed","error":"ffmpeg failed"},
				{"episode":3,"title":"Без сезона","status":"ready","download_url":"/downloads/c","filename":"c.mp4"}
			]
		}`))
	}))
	defer server.Close()

	loader := NewMediaLoader(server.URL, "", t.TempDir(), 1<<20, time.Second,
		fakeUploadEnqueuer{}, fakeTranscodeEnqueuer{})
	var received []CollectionEpisode
	err := loader.RunCollection(context.Background(),
		MediaLoaderRequest{URL: "https://example.com/series"}, "season",
		nil,
		func(episode CollectionEpisode) error {
			received = append(received, episode)
			return nil
		},
	)
	require.NoError(t, err)
	require.Len(t, received, 3)
	require.Equal(t, "ready", received[0].Status)
	require.Equal(t, 1, received[0].Season)
	require.Equal(t, "failed", received[1].Status)
	require.Equal(t, "ffmpeg failed", received[1].Error)
	require.Empty(t, received[1].DownloadURL)
	// Без номера сезона подставляется 1, номер серии берётся из поля.
	require.Equal(t, 1, received[2].Season)
	require.Equal(t, 3, received[2].Episode)
}

type fakeUploadEnqueuer struct{}

func (fakeUploadEnqueuer) Enqueue(UploadJobInput) (uint64, error) { return 0, nil }
func (fakeUploadEnqueuer) Status(uint64) (UploadJobStatus, bool)  { return UploadJobStatus{}, false }
func (fakeUploadEnqueuer) Cancel(uint64) error                    { return nil }

type fakeTranscodeEnqueuer struct{}

func (fakeTranscodeEnqueuer) Enqueue(string, string) (uint64, error) { return 0, nil }
func (fakeTranscodeEnqueuer) Get(uint64) (TranscodeJobStatus, bool) {
	return TranscodeJobStatus{}, false
}
func (fakeTranscodeEnqueuer) Cancel(uint64) error { return nil }
