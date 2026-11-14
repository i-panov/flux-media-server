package services

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"flux/internal/models"
)

// MediaLoader — клиент внешнего media-loader (yt-dlp/ffmpeg) и импортёр
// готового файла в карантин Flux. Задания живут в памяти: после рестарта
// незавершённый импорт нужно повторить, файл в media-loader при этом уже
// скачан и переиспользуется по кэшу.
type MediaLoader struct {
	baseURL     string
	token       string
	client      *http.Client
	download    *http.Client
	originals   string
	maxBytes    int64
	queue       uploadEnqueuer
	mu          sync.Mutex
	jobs        map[string]*MediaLoaderJob
	nextID      atomic.Uint64
	cleanupOnce sync.Once
}

// uploadEnqueuer — часть UploadQueue, нужная импортёру (и подменяемая в тестах).
type uploadEnqueuer interface {
	Enqueue(UploadJobInput) (uint64, error)
	Status(uint64) (UploadJobStatus, bool)
	Cancel(uint64) error
}

type MediaLoaderJob struct {
	ID          string    `json:"id"`
	Status      string    `json:"status"`
	Stage       string    `json:"stage,omitempty"`
	Progress    float64   `json:"progress,omitempty"`
	Error       string    `json:"error,omitempty"`
	UploadJobID uint64    `json:"upload_job_id,omitempty"`
	MediaID     uint      `json:"media_id,omitempty"`
	Title       string    `json:"title,omitempty"`
	Filename    string    `json:"filename,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	mediaType   models.MediaType
	cancel      context.CancelFunc
}

type MediaLoaderRequest struct {
	URL       string `json:"url"`
	AudioOnly bool   `json:"audio_only"`
	Format    string `json:"format,omitempty"`
	Quality   string `json:"quality,omitempty"`
}

type loaderResponse struct {
	Status     string `json:"status"`
	Stage      string `json:"stage"`
	RetryAfter int    `json:"retry_after"`
	Progress   struct {
		Percent float64 `json:"percent"`
		Stage   string  `json:"stage"`
	} `json:"progress"`
	DownloadURL string `json:"download_url"`
	Filename    string `json:"filename"`
	ContentType string `json:"content_type"`
	Title       string `json:"title"`
	Error       string `json:"error"`
	Detail      string `json:"detail"`
}

var (
	ErrMediaLoaderDisabled = errors.New("media loader is not configured")
	ErrMediaLoaderJobGone  = errors.New("media loader job not found")
)

func NewMediaLoader(cfgURL, token, originals string, maxBytes int64, timeout time.Duration, queue uploadEnqueuer) *MediaLoader {
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	m := &MediaLoader{
		baseURL:   strings.TrimRight(cfgURL, "/"),
		token:     token,
		client:    &http.Client{Timeout: timeout},
		download:  &http.Client{Timeout: 0},
		originals: originals,
		maxBytes:  maxBytes,
		queue:     queue,
		jobs:      make(map[string]*MediaLoaderJob),
	}
	return m
}

func (m *MediaLoader) Enabled() bool {
	return m != nil && m.baseURL != "" && m.queue != nil
}

// Submit запускает импорт и возвращает локальный id для polling.
func (m *MediaLoader) Submit(req MediaLoaderRequest) (MediaLoaderJob, error) {
	if !m.Enabled() {
		return MediaLoaderJob{}, ErrMediaLoaderDisabled
	}
	req.URL = strings.TrimSpace(req.URL)
	parsed, err := url.Parse(req.URL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return MediaLoaderJob{}, fmt.Errorf("invalid video URL")
	}
	if req.AudioOnly && req.Quality != "" {
		return MediaLoaderJob{}, fmt.Errorf("quality is not supported for audio")
	}
	id := m.newID()
	ctx, cancel := context.WithCancel(context.Background())
	now := time.Now()
	mediaType := models.MediaTypeVideo
	if req.AudioOnly {
		mediaType = models.MediaTypeAudio
	}
	job := &MediaLoaderJob{
		ID: id, Status: "queued", Stage: "queued", mediaType: mediaType,
		CreatedAt: now, UpdatedAt: now, cancel: cancel,
	}
	m.mu.Lock()
	m.jobs[id] = job
	m.mu.Unlock()
	m.cleanupOnce.Do(func() { go m.cleanupLoop() })
	go m.run(ctx, job, req)
	return m.snapshot(job), nil
}

func (m *MediaLoader) Get(id string) (MediaLoaderJob, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	job, ok := m.jobs[id]
	if !ok {
		return MediaLoaderJob{}, false
	}
	return *job, true
}

func (m *MediaLoader) Cancel(id string) error {
	m.mu.Lock()
	job, ok := m.jobs[id]
	if !ok {
		m.mu.Unlock()
		return ErrMediaLoaderJobGone
	}
	cancel := job.cancel
	job.Status = "cancelled"
	job.Error = "cancelled"
	job.UpdatedAt = time.Now()
	m.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if job.UploadJobID != 0 {
		_ = m.queue.Cancel(job.UploadJobID)
	}
	return nil
}

func (m *MediaLoader) snapshot(job *MediaLoaderJob) MediaLoaderJob {
	cp := *job
	cp.cancel = nil
	return cp
}

func (m *MediaLoader) set(job *MediaLoaderJob, status, stage string, progress float64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.Status == "cancelled" {
		return
	}
	job.Status = status
	if stage != "" {
		job.Stage = stage
	}
	if progress < 0 {
		progress = 0
	}
	if progress > 100 {
		progress = 100
	}
	job.Progress = progress
	job.UpdatedAt = time.Now()
}

func (m *MediaLoader) fail(job *MediaLoaderJob, err error) {
	if err == nil {
		err = errors.New("media loader failed")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.Status == "cancelled" {
		return
	}
	job.Status = "error"
	job.Error = err.Error()
	job.UpdatedAt = time.Now()
}

func (m *MediaLoader) run(ctx context.Context, job *MediaLoaderJob, req MediaLoaderRequest) {
	for {
		if ctx.Err() != nil {
			return
		}
		body, err := json.Marshal(map[string]any{
			"url": req.URL, "audio_only": req.AudioOnly,
			"format": req.Format, "quality": req.Quality,
			"respond_json": true,
		})
		if err != nil {
			m.fail(job, err)
			return
		}
		httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, m.baseURL+"/videos", strings.NewReader(string(body)))
		if err != nil {
			m.fail(job, err)
			return
		}
		httpReq.Header.Set("Content-Type", "application/json")
		if m.token != "" {
			httpReq.Header.Set("Authorization", "Bearer "+m.token)
		}
		resp, err := m.client.Do(httpReq)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			m.fail(job, err)
			return
		}
		data, readErr := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		if readErr != nil {
			m.fail(job, readErr)
			return
		}
		var out loaderResponse
		_ = json.Unmarshal(data, &out)
		switch resp.StatusCode {
		case http.StatusAccepted:
			stage := out.Stage
			if out.Progress.Stage != "" {
				stage = out.Progress.Stage
			}
			m.set(job, "downloading", stage, out.Progress.Percent)
			delay := time.Duration(out.RetryAfter) * time.Second
			if delay <= 0 {
				delay = 5 * time.Second
			}
			if !sleepContext(ctx, delay) {
				return
			}
		case http.StatusOK:
			if out.DownloadURL == "" {
				m.fail(job, fmt.Errorf("media loader returned no download_url"))
				return
			}
			// media-loader уже отдал файл; перенос в карантин локальный,
			// байтового прогресса у него нет — сбрасываем шкалу.
			m.set(job, "importing", "importing", 0)
			if err := m.importFile(ctx, job, out); err != nil {
				m.fail(job, err)
				return
			}
			return
		default:
			msg := out.Detail
			if msg == "" {
				msg = out.Error
			}
			if msg == "" {
				msg = strings.TrimSpace(string(data))
			}
			if msg == "" {
				msg = http.StatusText(resp.StatusCode)
			}
			m.fail(job, fmt.Errorf("media loader: %s", msg))
			return
		}
	}
}

func (m *MediaLoader) importFile(ctx context.Context, job *MediaLoaderJob, out loaderResponse) error {
	if out.Title != "" {
		m.mu.Lock()
		job.Title = out.Title
		m.mu.Unlock()
	}
	ref, err := url.Parse(out.DownloadURL)
	if err != nil {
		return err
	}
	base, _ := url.Parse(m.baseURL + "/")
	downloadURL := base.ResolveReference(ref).String()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, nil)
	if err != nil {
		return err
	}
	resp, err := m.download.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("media loader download: %s", resp.Status)
	}
	if err := os.MkdirAll(m.originals, 0750); err != nil {
		return err
	}
	filename := safeLoaderFilename(out.Filename)
	if filename == "" {
		filename = "download-" + job.ID
	}
	ext := filepath.Ext(filename)
	if ext == "" {
		if out.ContentType == "video/mp4" {
			ext = ".mp4"
		} else {
			ext = ".bin"
		}
		filename += ext
	}
	tmp, err := os.CreateTemp(m.originals, ".loader-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	written, copyErr := io.Copy(tmp, io.LimitReader(resp.Body, m.maxBytes+1))
	closeErr := tmp.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}
	if written > m.maxBytes {
		return fmt.Errorf("downloaded file exceeds max upload size")
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	final := uniqueLoaderPath(m.originals, filename)
	if err := os.Rename(tmpPath, final); err != nil {
		return err
	}
	m.mu.Lock()
	job.Filename = filepath.Base(final)
	m.mu.Unlock()
	mediaType := job.mediaType
	if strings.HasPrefix(out.ContentType, "audio/") {
		mediaType = models.MediaTypeAudio
	}
	if ctx.Err() != nil {
		_ = os.Remove(final)
		return ctx.Err()
	}
	uploadID, err := m.queue.Enqueue(UploadJobInput{
		FilePath: final, Filename: filepath.Base(final), MediaType: mediaType,
	})
	if err != nil {
		_ = os.Remove(final)
		return err
	}
	m.mu.Lock()
	job.UploadJobID = uploadID
	job.Status = "processing"
	job.Stage = "upload"
	job.UpdatedAt = time.Now()
	m.mu.Unlock()
	m.monitorUpload(job, uploadID)
	return nil
}

func (m *MediaLoader) monitorUpload(job *MediaLoaderJob, uploadID uint64) {
	deadline := time.Now().Add(6 * time.Hour)
	for time.Now().Before(deadline) {
		snap, ok := m.queue.Status(uploadID)
		if ok {
			switch snap.Status {
			case UploadJobDone:
				m.mu.Lock()
				job.Status = "done"
				job.Stage = "done"
				job.MediaID = snap.MediaID
				job.Progress = 100
				job.UpdatedAt = time.Now()
				m.mu.Unlock()
				return
			case UploadJobError, UploadJobDuplicate:
				msg := snap.Error
				if msg == "" {
					msg = snap.Status
				}
				m.fail(job, errors.New(msg))
				return
			}
		}
		time.Sleep(2 * time.Second)
	}
	m.fail(job, errors.New("upload processing timeout"))
}

func (m *MediaLoader) cleanupLoop() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-24 * time.Hour)
		m.mu.Lock()
		for id, job := range m.jobs {
			if job.UpdatedAt.Before(cutoff) && (job.Status == "done" || job.Status == "error" || job.Status == "cancelled") {
				delete(m.jobs, id)
			}
		}
		m.mu.Unlock()
	}
}

func (m *MediaLoader) newID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err == nil {
		return hex.EncodeToString(b[:])
	}
	return strconv.FormatUint(m.nextID.Add(1), 10)
}

func safeLoaderFilename(name string) string {
	name = filepath.Base(strings.TrimSpace(strings.ReplaceAll(name, "\\", "/")))
	name = strings.Trim(name, ". ")
	if name == "" || name == "." || name == ".." {
		return ""
	}
	return name
}

func uniqueLoaderPath(dir, name string) string {
	ext := filepath.Ext(name)
	stem := strings.TrimSuffix(name, ext)
	candidate := filepath.Join(dir, name)
	for i := 1; ; i++ {
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
		candidate = filepath.Join(dir, fmt.Sprintf("%s-%d%s", stem, i, ext))
	}
}

func sleepContext(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}
