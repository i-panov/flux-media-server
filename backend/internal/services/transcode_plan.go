package services

import (
	"fmt"
	"strconv"
	"strings"

	"gopkg.in/vansante/go-ffprobe.v2"
)

// NormalizeKind — решение классификатора, что делать с исходником.
type NormalizeKind string

const (
	// NormalizeDirect — файл уже домашний: переместить как есть.
	NormalizeDirect NormalizeKind = "direct"
	// NormalizeRemux — всё совместимо, только смена контейнера (-c copy).
	NormalizeRemux NormalizeKind = "remux"
	// NormalizeAudio — видео в порядке, аудио чинится (копия видео +
	// выборочный AAC). Дешевле полного транскода на порядки.
	NormalizeAudio NormalizeKind = "audio"
	// NormalizeFull — полный транскод видео в H.264, аудио выборочно.
	NormalizeFull NormalizeKind = "full"
)

// TextSubtitleCodecs — текстовые субтитры: извлекаются в WebVTT-сайдкары
// и копируются в MP4 как mov_text. Остальные (bitmaps) остаются только
// в оригинале: браузер их не показывает.
var TextSubtitleCodecs = map[string]bool{
	"subrip": true, "srt": true,
	"ass": true, "ssa": true,
	"mov_text": true, "webvtt": true,
}

// BrowserSafeAudio — аудиокодеки, которые и пакуются в MP4, и прямо
// играются weakest-клиентом (Vidaa-Chromium: AAC/MP3 наверняка, Opus/FLAC
// под вопросом). Всё остальное — в AAC при приёме: домашний формат
// обязан играться без серверного транскода в момент просмотра.
var BrowserSafeAudio = map[string]bool{
	"aac": true, "mp3": true,
}

// SubTrack — текстовая субтитровая дорожка для извлечения.
type SubTrack struct {
	// Index — индекс потока в исходнике для -map 0:<index>.
	Index int
	Codec string
	Lang  string
}

// ProbeResult — сжатая выжимка ffprobe, нужная классификатору.
// Собственная структура вместо *ffprobe.ProbeData: классификатор
// тестируется фикстурами без ffmpeg.
type ProbeResult struct {
	Container   string
	DurationSec float64
	HasVideo    bool
	VideoCodec  string
	// VideoIndex — индекс выбранного видеопотока (первый не-обложка).
	// Маппим поток явно, а не 0:v:0: если первым идёт attached-pic
	// (обложка), 0:v:0 перекодировал бы картинку вместо видео.
	VideoIndex int
	Width      int
	Height     int
	// PixFmt — пиксельный формат (yuv420p и др.). Пусто — считать
	// небезопасным: слабый клиент 10-bit/4:2:2 не играет.
	PixFmt   string
	HasAudio bool
	// AudioCodecs — кодеки аудиодорожек по порядку потоков.
	AudioCodecs   []string
	TextSubs      []SubTrack
	HasBitmapSubs bool
	Chapters      int
}

// ProbeFromData сворачивает полный результат ffprobe. data == nil или
// отсутствие видеопотока — не ошибка парсинга, а пустой результат:
// решение по нему принимает классификатор.
func ProbeFromData(data *ffprobe.ProbeData) ProbeResult {
	var probe ProbeResult
	if data == nil || data.Format == nil {
		return probe
	}
	probe.Container = data.Format.FormatName
	if dur := data.Format.Duration(); dur > 0 {
		probe.DurationSec = dur.Seconds()
	}
	probe.Chapters = len(data.Chapters)
	for _, s := range data.Streams {
		switch s.CodecType {
		case "video":
			// Встроенная обложка (mjpeg/png/...) — не видео,
			// тот же список, что в DetermineMediaTypeFromProbe.
			codec := strings.ToLower(s.CodecName)
			switch codec {
			case "mjpeg", "png", "jpegls", "bmp", "gif", "tiff":
				continue
			}
			if !probe.HasVideo {
				probe.HasVideo = true
				probe.VideoCodec = codec
				probe.VideoIndex = s.Index
				probe.PixFmt = strings.ToLower(s.PixFmt)
				probe.Width = s.Width
				probe.Height = s.Height
			}
		case "audio":
			probe.HasAudio = true
			probe.AudioCodecs = append(probe.AudioCodecs, strings.ToLower(s.CodecName))
		case "subtitle":
			codec := strings.ToLower(s.CodecName)
			if TextSubtitleCodecs[codec] {
				lang, _ := s.TagList.GetString("language")
				if lang == "" {
					lang = "und"
				}
				probe.TextSubs = append(probe.TextSubs, SubTrack{
					Index: s.Index,
					Codec: codec,
					Lang:  strings.ToLower(lang),
				})
			} else {
				probe.HasBitmapSubs = true
			}
		}
	}
	return probe
}

// NormalizePlan — решение классификатора и параметры нормализации.
type NormalizePlan struct {
	Kind       NormalizeKind
	NeedScale  bool // downscale до MaxHeight (только full)
	VideoIndex int
	HasAudio   bool
	// AudioCodecs — по порядку потоков; для несовместимых строится
	// персональный -c:a:N aac (см. audioCodecArgs).
	AudioCodecs []string
	SubTracks   []SubTrack
	DurationSec float64
}

// HouseVideoCodec — видеокодек домашнего формата.
const HouseVideoCodec = "h264"

// HousePixFmt — единственный пиксельный формат домашнего видео:
// 8-bit 4:2:0 играет weakest-клиент. 10-bit (High 10), 4:2:2/4:4:4,
// неизвестный — в полный транскод. Профили отдельно не проверяем:
// у H.264 с yuv420p все массовые профили (Baseline/Main/High) играбельны.
const HousePixFmt = "yuv420p"

// audioCompatible — все аудиодорожки прямо играются (пусто — vacuously true).
func audioCompatible(codecs []string) bool {
	for _, codec := range codecs {
		if !BrowserSafeAudio[codec] {
			return false
		}
	}
	return true
}

// ClassifyPlan решает, что делать с файлом. Без видеопотока или
// без размеров кадра — full: безопасное направление (гарантированно
// играбельный результат), такие файлы редки.
func ClassifyPlan(probe ProbeResult, maxHeight int) NormalizePlan {
	plan := NormalizePlan{
		Kind:        NormalizeFull,
		VideoIndex:  probe.VideoIndex,
		HasAudio:    probe.HasAudio,
		AudioCodecs: probe.AudioCodecs,
		SubTracks:   probe.TextSubs,
		DurationSec: probe.DurationSec,
	}
	if !probe.HasVideo || probe.Height <= 0 {
		return plan
	}
	videoOK := probe.VideoCodec == HouseVideoCodec && probe.PixFmt == HousePixFmt && probe.Height <= maxHeight
	audioOK := audioCompatible(probe.AudioCodecs)
	if videoOK && audioOK {
		if isMP4Container(probe.Container) {
			plan.Kind = NormalizeDirect
			return plan
		}
		plan.Kind = NormalizeRemux
		return plan
	}
	if videoOK {
		plan.Kind = NormalizeAudio
		return plan
	}
	if probe.Height > maxHeight {
		plan.NeedScale = true
	}
	return plan
}

// isMP4Container проверяет контейнер по имени формата ffprobe
// ("mov,mp4,m4a,3gp,3g2,mj2" и варианты).
func isMP4Container(formatName string) bool {
	for part := range strings.SplitSeq(formatName, ",") {
		switch strings.ToLower(strings.TrimSpace(part)) {
		case "mp4", "m4v", "mov":
			return true
		}
	}
	return false
}

// ffmpegStreamMaps — общие маппинги: явный видеопоток (не 0:v:0 —
// см. VideoIndex), всё аудио, текстовые сабы, главы. Bitmap-дорожки
// не маппятся (MP4 их не умеет, а падать из-за них нельзя).
func ffmpegStreamMaps(plan NormalizePlan) []string {
	args := []string{"-map", fmt.Sprintf("0:%d", plan.VideoIndex)}
	if plan.HasAudio {
		args = append(args, "-map", "0:a?")
	}
	for _, sub := range plan.SubTracks {
		args = append(args, "-map", fmt.Sprintf("0:%d", sub.Index))
	}
	return append(args, "-map_chapters", "0")
}

// audioCodecArgs — покодековые -c:a:N: совместимые копируются,
// остальные — в AAC. Порядок выходных дорожек совпадает с входным
// (все аудио маппятся), поэтому индекс N точен.
func audioCodecArgs(codecs []string) []string {
	var args []string
	for i, codec := range codecs {
		if BrowserSafeAudio[codec] {
			args = append(args, fmt.Sprintf("-c:a:%d", i), "copy")
		} else {
			args = append(args, fmt.Sprintf("-c:a:%d", i), "aac")
		}
	}
	return args
}

// FFmpegConvertArgs строит аргументы полного транскода: видео — libx264
// (CRF/preset из конфига, даунскейл при нужде), аудио — выборочно,
// текстовые субтитры — в mov_text. `-n`: перезапись — только через
// проверку уникальности и commit после успеха.
func FFmpegConvertArgs(src, dst string, plan NormalizePlan, crf int, preset string, maxHeight int) []string {
	args := []string{"-i", src, "-n"}
	args = append(args, ffmpegStreamMaps(plan)...)
	args = append(args, "-c:v", "libx264", "-preset", preset, "-crf", strconv.Itoa(crf))
	// Форсируем 8-bit 4:2:0: иначе libx264 сохранит 10-bit исходника
	// (High 10), который weakest-клиент не играет.
	args = append(args, "-pix_fmt", HousePixFmt)
	if plan.NeedScale {
		args = append(args, "-vf", fmt.Sprintf("scale=-2:'min(%d,ih)'", maxHeight))
	}
	args = append(args, audioCodecArgs(plan.AudioCodecs)...)
	args = append(args, "-c:s", "mov_text", "-movflags", "+faststart")
	return append(args, dst)
}

// FFmpegAudioFixArgs — видео копией, аудио выборочно в AAC. Для файлов,
// чьё видео уже в порядке: на порядки дешевле полного транскода.
func FFmpegAudioFixArgs(src, dst string, plan NormalizePlan) []string {
	args := []string{"-i", src, "-n"}
	args = append(args, ffmpegStreamMaps(plan)...)
	args = append(args, "-c:v", "copy")
	args = append(args, audioCodecArgs(plan.AudioCodecs)...)
	args = append(args, "-c:s", "mov_text", "-movflags", "+faststart")
	return append(args, dst)
}

// FFmpegRemuxArgs — смена контейнера без перекодирования. Вызывается
// только для полностью совместимых файлов (проверяет классификатор).
func FFmpegRemuxArgs(src, dst string, plan NormalizePlan) []string {
	args := []string{"-i", src, "-n"}
	args = append(args, ffmpegStreamMaps(plan)...)
	args = append(args, "-c", "copy", "-c:s", "mov_text", "-movflags", "+faststart")
	return append(args, dst)
}

// FFmpegSubExtractArgs — извлечение ОДНОЙ текстовой дорожки в WebVTT.
// Строго одна выходная секция на вызов: общий -map на несколько выходов
// ffmpeg применяет только к первому, а WebVTT-муксер многопоточность
// не поддерживает — команда с двумя дорожками падает целиком.
// Флага перезаписи нет специально: его добавляет раннер (-y — сайдкар
// перегенерируем, ретрай не должен спотыкаться о прошлую попытку).
func FFmpegSubExtractArgs(src string, sub SubTrack, output string) []string {
	return []string{
		"-i", src,
		"-map", fmt.Sprintf("0:%d", sub.Index),
		"-c:s", "webvtt",
		output,
	}
}

// ProgressUpdate — распарсенная строка -progress: проценты и скорость.
type ProgressUpdate struct {
	Percent float64
	Speed   float64
	// Done — встречен progress=end.
	Done bool
}

// ParseProgressLine разбирает одну строку `-progress` ffmpeg
// (out_time_ms=..., speed=..., progress=...). durationSecs — длительность
// из probe (0 — проценты не считаются). Возвращает ok=false для строк,
// не несущих прогресса.
func ParseProgressLine(line string, durationSecs float64) (update ProgressUpdate, ok bool) {
	line = strings.TrimSpace(line)
	if strings.HasPrefix(line, "out_time_ms=") {
		micros, err := strconv.ParseInt(strings.TrimPrefix(line, "out_time_ms="), 10, 64)
		if err != nil || micros < 0 {
			return ProgressUpdate{}, false
		}
		update.Percent = 100
		if durationSecs > 0 {
			update.Percent = float64(micros) / (durationSecs * 1_000_000) * 100
		}
		if update.Percent < 0 {
			update.Percent = 0
		}
		if update.Percent > 100 {
			update.Percent = 100
		}
		return update, true
	}
	if strings.HasPrefix(line, "speed=") {
		speedStr := strings.TrimSuffix(strings.TrimPrefix(line, "speed="), "x")
		speed, err := strconv.ParseFloat(strings.TrimSpace(speedStr), 64)
		if err != nil || speed < 0 {
			return ProgressUpdate{}, false
		}
		update.Speed = speed
		return update, true
	}
	if line == "progress=end" {
		return ProgressUpdate{Percent: 100, Done: true}, true
	}
	return ProgressUpdate{}, false
}
