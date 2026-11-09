package services

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"log"
	"os/exec"
	"time"

	"gopkg.in/vansante/go-ffprobe.v2"
)

// FFmpegRunner — выполнение ffmpeg/ffprobe. Интерфейс ради тестов:
// реальный раннер дергает бинарники, фейковый в тестах отдаёт canned-ответы.
type FFmpegRunner interface {
	Probe(ctx context.Context, path string) (ProbeResult, error)
	// TranscodeVideo нормализует видео по плану (full). progress
	// вызывается из горутины чтения пайпа; вызовы после возврата
	// ошибки вызывающий обязан игнорировать.
	TranscodeVideo(ctx context.Context, src, dst string, plan NormalizePlan, opts TranscodeOptions, progress func(ProgressUpdate)) error
	// RemuxCopy меняет контейнер без перекодирования.
	RemuxCopy(ctx context.Context, src, dst string, plan NormalizePlan) error
	// FixAudio чинит аудиодорожки (выборочный AAC, видео копией) для
	// файлов, чьё видео уже в порядке. Дешевле полного транскода
	// на порядки; прогресс отслеживается так же.
	FixAudio(ctx context.Context, src, dst string, plan NormalizePlan, timeoutCap time.Duration, progress func(ProgressUpdate)) error
	// ExtractSubtitles извлекает ОДНУ текстовую дорожку в WebVTT-файл.
	// Один вызов — одна дорожка: общий -map на несколько выходов ffmpeg
	// применяет только к первому. -y вместо -n: сайдкар перегенерируем,
	// ретрай не должен спотыкаться о файл прошлой попытки.
	ExtractSubtitles(ctx context.Context, src string, sub SubTrack, output string) error
}

// TranscodeOptions — параметры кодирования из конфига.
type TranscodeOptions struct {
	CRF       int
	Preset    string
	MaxHeight int
	// TimeoutCap — потолок времени одного файла.
	TimeoutCap time.Duration
}

// SystemFFmpegRunner — настоящий раннер поверх бинарников из PATH.
type SystemFFmpegRunner struct {
	// nicePath — путь к nice, "" — запускать напрямую. Определяется
	// один раз: nice снижает приоритет CPU ffmpeg, чтобы интерфейс
	// не лагал во время счёта.
	nicePath string
}

// NewSystemFFmpegRunner создаёт раннер. Отсутствие nice — не ошибка,
// просто без понижения приоритета.
func NewSystemFFmpegRunner() *SystemFFmpegRunner {
	path, err := exec.LookPath("nice")
	if err != nil {
		log.Printf("transcode: nice not found, ffmpeg runs at normal priority")
		return &SystemFFmpegRunner{}
	}
	return &SystemFFmpegRunner{nicePath: path}
}

// ffmpegCmd строит команду с пониженным приоритетом при наличии nice.
func (r *SystemFFmpegRunner) ffmpegCmd(ctx context.Context, args ...string) *exec.Cmd {
	if r.nicePath != "" {
		full := append([]string{"-n", "10", "ffmpeg"}, args...)
		return exec.CommandContext(ctx, r.nicePath, full...)
	}
	return exec.CommandContext(ctx, "ffmpeg", args...)
}

// Probe читает потоки через ffprobe с таймаутом.
func (r *SystemFFmpegRunner) Probe(ctx context.Context, path string) (ProbeResult, error) {
	probeCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	data, err := ffprobe.ProbeURL(probeCtx, path)
	if err != nil {
		return ProbeResult{}, err
	}
	probe := ProbeFromData(data)
	probe.Filename = path
	return probe, nil
}

// TranscodeVideo запускает ffmpeg с -progress пайпом: проценты и скорость
// парсятся потоково, без ожидания конца файла. -progress вставляется
// перед файлом назначения: порядок аргументов ffmpeg важен.
func (r *SystemFFmpegRunner) TranscodeVideo(ctx context.Context, src, dst string, plan NormalizePlan, opts TranscodeOptions, progress func(ProgressUpdate)) error {
	timeout := transcodeTimeout(plan.DurationSec, opts.TimeoutCap)
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	base := FFmpegConvertArgs(src, dst, plan, opts.CRF, opts.Preset, opts.MaxHeight)
	args := make([]string, 0, len(base)+3)
	args = append(args, base[:len(base)-1]...)
	args = append(args, "-progress", "pipe:1", "-nostats", dst)

	cmd := r.ffmpegCmd(cmdCtx, args...)
	return r.runWithProgress(cmdCtx, cmd, plan.DurationSec, progress)
}

// FixAudio чинит аудио (видео копией). Прогресс отслеживается,
// как в TranscodeVideo: для часовых файлов тишина хуже цифр.
func (r *SystemFFmpegRunner) FixAudio(ctx context.Context, src, dst string, plan NormalizePlan, timeoutCap time.Duration, progress func(ProgressUpdate)) error {
	timeout := transcodeTimeout(plan.DurationSec, timeoutCap)
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	base := FFmpegAudioFixArgs(src, dst, plan)
	args := make([]string, 0, len(base)+3)
	args = append(args, base[:len(base)-1]...)
	args = append(args, "-progress", "pipe:1", "-nostats", dst)

	cmd := r.ffmpegCmd(cmdCtx, args...)
	return r.runWithProgress(cmdCtx, cmd, plan.DurationSec, progress)
}

// RemuxCopy — смена контейнера, прогресс не отслеживаем (секунды).
func (r *SystemFFmpegRunner) RemuxCopy(ctx context.Context, src, dst string, plan NormalizePlan) error {
	cmdCtx, cancel := context.WithTimeout(ctx, 10*time.Minute)
	defer cancel()

	cmd := r.ffmpegCmd(cmdCtx, FFmpegRemuxArgs(src, dst, plan)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg remux: %w: %s", err, stderr.String())
	}
	return nil
}

// ExtractSubtitles извлекает одну дорожку. -y осознанно (см. выше):
// сайдкар детерминирован содержимым, перезапись безопасна.
func (r *SystemFFmpegRunner) ExtractSubtitles(ctx context.Context, src string, sub SubTrack, output string) error {
	cmdCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	base := FFmpegSubExtractArgs(src, sub, output)
	args := make([]string, 0, len(base)+1)
	args = append(args, base[:len(base)-1]...)
	args = append(args, "-y", output)

	cmd := r.ffmpegCmd(cmdCtx, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ffmpeg subtitles: %w: %s", err, stderr.String())
	}
	return nil
}

// runWithProgress запускает команду и парсит -progress из stdout построчно.
// Пайп вычитывается всегда (иначе ffmpeg встанет при переполнении буфера),
// колбэк вызывается только если задан. Паттерн ошибок — как у thumbSvc:
// stderr в буфер для диагностики.
func (r *SystemFFmpegRunner) runWithProgress(ctx context.Context, cmd *exec.Cmd, durationSecs float64, progress func(ProgressUpdate)) error {
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("ffmpeg progress pipe: %w", err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("ffmpeg start: %w", err)
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 64*1024), 64*1024)
	for scanner.Scan() {
		if ctx.Err() != nil || progress == nil {
			continue
		}
		if update, ok := ParseProgressLine(scanner.Text(), durationSecs); ok {
			progress(update)
		}
	}

	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("ffmpeg: %w: %s", err, stderr.String())
	}
	return nil
}

// transcodeTimeout масштабирует лимит от длительности: скорость счёта
// непредсказуема (железо/пресет), фиксированный таймаут убивал бы длинные
// фильмы. Потолок — от зависшего ffmpeg навсегда. Минимум — короткие
// файлы тоже должны успевать на медленном железе.
func transcodeTimeout(durationSecs float64, cap time.Duration) time.Duration {
	timeout := time.Duration(durationSecs*4)*time.Second + 30*time.Minute
	if timeout > cap {
		timeout = cap
	}
	if timeout < 30*time.Minute {
		timeout = 30 * time.Minute
	}
	return timeout
}
