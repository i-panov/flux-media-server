package services

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestClassifyDirect(t *testing.T) {
	plan := ClassifyPlan(ProbeResult{
		Container:   "mov,mp4,m4a,3gp,3g2,mj2",
		Filename:    "film.mp4",
		HasVideo:    true,
		VideoCodec:  "h264",
		VideoIndex:  0,
		PixFmt:      "yuv420p",
		Width:       1920,
		Height:      1080,
		HasAudio:    true,
		AudioCodecs: []string{"aac"},
	}, 1080)
	assert.Equal(t, NormalizeDirect, plan.Kind)
	assert.False(t, plan.NeedScale)
	assert.True(t, plan.HasAudio)
}

func TestClassifyRemux(t *testing.T) {
	plan := ClassifyPlan(ProbeResult{
		Container:   "matroska,webm",
		HasVideo:    true,
		VideoCodec:  "h264",
		VideoIndex:  0,
		PixFmt:      "yuv420p",
		Width:       1920,
		Height:      1080,
		AudioCodecs: []string{"aac"},
	}, 1080)
	assert.Equal(t, NormalizeRemux, plan.Kind)
	assert.False(t, plan.NeedScale)
}

func TestClassifyAudioFix(t *testing.T) {
	// Видео в порядке, аудио нет — чиним только аудио, не трогая видео.
	for _, tc := range []struct {
		name   string
		codecs []string
	}{
		{"dts", []string{"dts"}},
		{"ac3-mixed", []string{"aac", "ac3"}},
		{"vorbis", []string{"vorbis"}},
		{"opus", []string{"opus"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			plan := ClassifyPlan(ProbeResult{
				Container:   "mov,mp4,m4a",
				HasVideo:    true,
				VideoCodec:  "h264",
				VideoIndex:  0,
				PixFmt:      "yuv420p",
				Width:       1920,
				Height:      1080,
				HasAudio:    true,
				AudioCodecs: tc.codecs,
			}, 1080)
			assert.Equal(t, NormalizeAudio, plan.Kind)
			assert.False(t, plan.NeedScale)
		})
	}
}

func TestClassifyCoverArtIndex(t *testing.T) {
	// Обложка первым видеопотоком: выбирается настоящее видео с его индексом.
	probe := ProbeResult{
		Container:   "matroska,webm",
		HasVideo:    true,
		VideoCodec:  "h264",
		VideoIndex:  1,
		PixFmt:      "yuv420p",
		Width:       1920,
		Height:      1080,
		AudioCodecs: []string{"aac"},
	}
	plan := ClassifyPlan(probe, 1080)
	assert.Equal(t, NormalizeRemux, plan.Kind)
	args := strings.Join(FFmpegRemuxArgs("in.mkv", "out.mp4", plan), " ")
	assert.Contains(t, args, "-map 0:1")
	assert.NotContains(t, args, "0:v:0")
}

func TestClassifyFullCases(t *testing.T) {
	for _, tc := range []struct {
		name  string
		probe ProbeResult
		scale bool
	}{
		{"hevc", ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc", Width: 1920, Height: 1080}, false},
		{"tall-h264", ProbeResult{Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", Width: 3840, Height: 2160}, true},
		{"10bit-h264", ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv420p10le", Width: 1920, Height: 1080}, false},
		{"422-h264", ProbeResult{Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264", PixFmt: "yuv422p", Width: 1920, Height: 1080}, false},
		{"hevc-10bit", ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc", PixFmt: "yuv420p10le", Width: 1920, Height: 1080}, false},
		{"tall-hevc", ProbeResult{Container: "matroska,webm", HasVideo: true, VideoCodec: "hevc", Width: 3840, Height: 2160}, true},
		{"no-video", ProbeResult{Container: "mp3"}, false},
		{"no-dims", ProbeResult{Container: "mov,mp4,m4a", HasVideo: true, VideoCodec: "h264"}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			plan := ClassifyPlan(tc.probe, 1080)
			assert.Equal(t, NormalizeFull, plan.Kind)
			assert.Equal(t, tc.scale, plan.NeedScale)
		})
	}
}

func TestProbeFromDataSubs(t *testing.T) {
	// Конструируем минимум через классификатор: текстовые vs bitmap.
	// Полный ProbeData собирается в transcode_queue_test (фейковый раннер).
	plan := ClassifyPlan(ProbeResult{
		Container: "matroska,webm",
		HasVideo:  true, VideoCodec: "hevc", Width: 1920, Height: 1080,
		HasAudio: true,
		TextSubs: []SubTrack{
			{Index: 2, Codec: "subrip", Lang: "rus"},
			{Index: 3, Codec: "ass", Lang: "eng"},
		},
		HasBitmapSubs: true,
	}, 1080)
	assert.Equal(t, NormalizeFull, plan.Kind)
	require.Len(t, plan.SubTracks, 2)
	assert.True(t, plan.HasAudio)
}

func TestConvertArgs(t *testing.T) {
	plan := NormalizePlan{
		Kind:        NormalizeFull,
		NeedScale:   true,
		VideoIndex:  0,
		HasAudio:    true,
		AudioCodecs: []string{"dts", "aac"},
		SubTracks:   []SubTrack{{Index: 2, Codec: "subrip", Lang: "rus"}},
	}
	args := FFmpegConvertArgs("in.mkv", "out.mp4", plan, 20, "fast", 1080)
	joined := strings.Join(args, " ")
	assert.Contains(t, joined, "-c:v libx264")
	assert.Contains(t, joined, "-preset fast")
	assert.Contains(t, joined, "-crf 20")
	assert.Contains(t, joined, "-pix_fmt yuv420p")
	assert.Contains(t, joined, "-vf scale=-2:'min(1080,ih)'")
	assert.Contains(t, joined, "-map 0:0")
	assert.NotContains(t, joined, "-map 0:v:0")
	assert.Contains(t, joined, "-map 0:a?")
	assert.Contains(t, joined, "-map 0:2")
	// Покодеково: dts → aac, aac → copy.
	assert.Contains(t, joined, "-c:a:0 aac")
	assert.Contains(t, joined, "-c:a:1 copy")
	assert.Contains(t, joined, "-c:s mov_text")
	assert.Contains(t, joined, "-map_chapters 0")
	assert.Contains(t, joined, "-movflags +faststart")
	assert.Contains(t, joined, "-n")
	assert.Equal(t, "out.mp4", args[len(args)-1])

	// Без аудио и без даунскейла лишнего нет.
	plain := NormalizePlan{Kind: NormalizeFull}
	plainArgs := strings.Join(FFmpegConvertArgs("in.mkv", "out.mp4", plain, 23, "veryfast", 1080), " ")
	assert.NotContains(t, plainArgs, "0:a?")
	assert.NotContains(t, plainArgs, "-vf")
}

func TestAudioFixArgs(t *testing.T) {
	plan := NormalizePlan{
		Kind:        NormalizeAudio,
		VideoIndex:  0,
		HasAudio:    true,
		AudioCodecs: []string{"ac3"},
	}
	joined := strings.Join(FFmpegAudioFixArgs("in.mp4", "out.mp4", plan), " ")
	assert.Contains(t, joined, "-c:v copy")
	assert.NotContains(t, joined, "libx264")
	assert.Contains(t, joined, "-c:a:0 aac")
	assert.Contains(t, joined, "-movflags +faststart")
}

func TestRemuxArgs(t *testing.T) {
	plan := NormalizePlan{Kind: NormalizeRemux, HasAudio: true}
	joined := strings.Join(FFmpegRemuxArgs("in.mkv", "out.mp4", plan), " ")
	assert.Contains(t, joined, "-c copy")
	assert.NotContains(t, joined, "libx264")
	assert.Contains(t, joined, "-movflags +faststart")
}

func TestSubExtractArgs(t *testing.T) {
	// Строго одна дорожка на вызов: общий -map на несколько выходов
	// ffmpeg применяет только к первому.
	args := FFmpegSubExtractArgs("in.mkv", SubTrack{Index: 4, Codec: "ass", Lang: "eng"}, "o.eng.vtt")
	joined := strings.Join(args, " ")
	assert.Contains(t, joined, "-map 0:4")
	assert.Contains(t, joined, "-c:s webvtt")
	assert.NotContains(t, joined, "-n")
	assert.Equal(t, "o.eng.vtt", args[len(args)-1])
}

func TestSanitizeLang(t *testing.T) {
	assert.Equal(t, "rus", sanitizeLang("rus"))
	assert.Equal(t, "sr-latn-rs", sanitizeLang("sr-latn-rs"))
	assert.Equal(t, "und", sanitizeLang(""))
	assert.Equal(t, "und", sanitizeLang("--"))
	assert.Equal(t, "und", sanitizeLang("x"))
	assert.Equal(t, "und", sanitizeLang("this-language-tag-is-way-too-long"))
	assert.True(t, ValidSubtitleLang("rus2"))
	assert.True(t, ValidSubtitleLang("sr-latn-rs"))
	assert.False(t, ValidSubtitleLang("x"))
}

func TestParseProgressLine(t *testing.T) {
	update, ok := ParseProgressLine("out_time_ms=60000000", 120)
	require.True(t, ok)
	assert.InDelta(t, 50.0, update.Percent, 0.001)
	assert.False(t, update.Done)

	update, ok = ParseProgressLine("speed=2.5x", 0)
	require.True(t, ok)
	assert.InDelta(t, 2.5, update.Speed, 0.001)

	update, ok = ParseProgressLine("progress=end", 0)
	require.True(t, ok)
	assert.True(t, update.Done)
	assert.Equal(t, 100.0, update.Percent)

	// Мусор и переполнение клампятся/отбрасываются.
	_, ok = ParseProgressLine("frame=123", 0)
	assert.False(t, ok)
	update, ok = ParseProgressLine("out_time_ms=999999999999", 10)
	require.True(t, ok)
	assert.Equal(t, 100.0, update.Percent)
	_, ok = ParseProgressLine("out_time_ms=abc", 10)
	assert.False(t, ok)

	// Без длительности проценты не считаются, но строка валидна.
	update, ok = ParseProgressLine("out_time_ms=1000", 0)
	require.True(t, ok)
	assert.Equal(t, 100.0, update.Percent)
}

func TestClassifyPlanRemuxesMOV(t *testing.T) {
	// QuickTime-контейнер не гарантированно играет в браузере: даже с
	// h264/aac его надо ремуксить в mp4, а не отдавать direct.
	plan := ClassifyPlan(ProbeResult{
		Container:   "mov,mp4,m4a,3gp,3g2,mj2",
		Filename:    "film.mov",
		HasVideo:    true,
		VideoCodec:  "h264",
		PixFmt:      "yuv420p",
		Width:       1920,
		Height:      1080,
		HasAudio:    true,
		AudioCodecs: []string{"aac"},
	}, 1080)
	assert.Equal(t, NormalizeRemux, plan.Kind)
}
