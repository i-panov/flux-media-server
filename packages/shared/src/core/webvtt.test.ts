import { describe, expect, it } from "vitest";
import { activeSubtitleText, parseWebVtt } from "./webvtt";

describe("parseWebVtt", () => {
	it("парсит таймкоды, идентификаторы и многострочный текст", () => {
		const cues = parseWebVtt(`\uFEFFWEBVTT

NOTE служебный блок

1
00:00:01.000 --> 00:00:03.500 align:start
Привет
мир

01:02:03,250 --> 01:02:05,000
Поздно
`);
		expect(cues).toEqual([
			{ start: 1, end: 3.5, text: "Привет\nмир" },
			{ start: 3723.25, end: 3725, text: "Поздно" },
		]);
	});

	it("пропускает битые блоки и пустой текст", () => {
		expect(parseWebVtt("")).toEqual([]);
		expect(
			parseWebVtt(`WEBVTT

00:00:05.000 --> 00:00:04.000
назад

00:00:01.000 --> 00:00:02.000
`),
		).toEqual([]);
	});

	it("снимает инлайн-разметку и ASS-оверрайды", () => {
		const [cue] = parseWebVtt(`WEBVTT

00:00:00.000 --> 00:00:01.000
<v Speaker><i>Привет</i> {\\an8}мир
`);
		expect(cue?.text).toBe("Привет мир");
	});

	it("декодирует сущности одним проходом", () => {
		const [cue] = parseWebVtt(`WEBVTT

00:00:00.000 --> 00:00:01.000
&amp;lt; &quot;x&quot; &#33;
`);
		expect(cue?.text).toBe('&lt; "x" !');
	});

	it("не путает cue с идентификатором NOTE1 с NOTE-блоком", () => {
		const cues = parseWebVtt(`WEBVTT

NOTE1
00:00:00.000 --> 00:00:01.000
текст
`);
		expect(cues).toHaveLength(1);
	});

	it("декодирует базовые HTML-сущности", () => {
		const [cue] = parseWebVtt(`WEBVTT

00:00:00.000 --> 00:00:01.000
A &amp; B &lt;3
`);
		expect(cue?.text).toBe("A & B <3");
	});
});

describe("activeSubtitleText", () => {
	const cues = parseWebVtt(`WEBVTT

00:00:01.000 --> 00:00:02.000
раз

00:00:03.000 --> 00:00:04.000
два
`);

	it("возвращает cue по позиции", () => {
		expect(activeSubtitleText(cues, 1.5)).toBe("раз");
		expect(activeSubtitleText(cues, 3.5)).toBe("два");
	});

	it("возвращает null между cue и до начала", () => {
		expect(activeSubtitleText(cues, 0.5)).toBeNull();
		expect(activeSubtitleText(cues, 2.5)).toBeNull();
		expect(activeSubtitleText(cues, 10)).toBeNull();
	});
});
