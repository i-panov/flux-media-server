package services

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestProbeSeriesAcceptsFractionalDuration(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
			"status":"ok","metadata_only":true,"collection":true,"scope":"series",
			"series":{"id":"rutube:1","title":"Сериал"},
			"seasons":[1],
			"episodes":[
				{"season":1,"episode":1,"title":"Серия 1","duration":1406.0},
				{"season":1,"episode":2,"title":"Серия 2","duration":null}
			],
			"episodes_total":2
		}`))
	}))
	defer server.Close()

	loader := NewMediaLoader(server.URL, "", t.TempDir(), 1<<20, time.Second,
		fakeUploadEnqueuer{}, fakeTranscodeEnqueuer{})
	probe, err := loader.ProbeSeries(context.Background(), "https://rutube.ru/video/1/")
	require.NoError(t, err)
	require.Equal(t, "series", probe.Kind)
	require.Len(t, probe.Episodes, 2)
	require.Equal(t, 1406, probe.Episodes[0].Duration)
	require.Equal(t, 0, probe.Episodes[1].Duration)
}

func TestProbeSingleVideoAcceptsFractionalDuration(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"title":"Клип","duration":95.5,"thumbnail":"https://example.com/t.jpg"}`))
	}))
	defer server.Close()

	loader := NewMediaLoader(server.URL, "", t.TempDir(), 1<<20, time.Second,
		fakeUploadEnqueuer{}, fakeTranscodeEnqueuer{})
	probe, err := loader.ProbeSeries(context.Background(), "https://example.com/clip")
	require.NoError(t, err)
	require.Equal(t, "episode", probe.Kind)
	require.Equal(t, 95, probe.Duration)
}
