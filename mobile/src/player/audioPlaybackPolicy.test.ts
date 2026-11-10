import { describe, expect, it } from "vitest";
import {
	desiredAfterStatus,
	shouldPauseOnToggle,
	shouldResumeAfterTrackChange,
	wasPlayingBeforeChange,
} from "./audioPlaybackPolicy";

function toggleState(overrides: {
	playing?: boolean;
	loading?: boolean;
	buffering?: boolean;
	desiredPlaying?: boolean;
}) {
	return {
		playing: false,
		loading: false,
		buffering: false,
		desiredPlaying: false,
		...overrides,
	};
}

describe("audio playback toggle policy", () => {
	it("после внешней паузы один тап play не превращается в no-op", () => {
		// desired остался true с момента старта, но нативный плеер уже
		// поставлен на паузу шторкой/наушниками — тап должен играть.
		expect(shouldPauseOnToggle(toggleState({ desiredPlaying: true }))).toBe(
			false,
		);
	});

	it("играющий трек ставится на паузу", () => {
		expect(shouldPauseOnToggle(toggleState({ playing: true }))).toBe(true);
	});

	it("повторный тап во время загрузки отменяет намерение", () => {
		expect(
			shouldPauseOnToggle(toggleState({ loading: true, desiredPlaying: true })),
		).toBe(true);
	});

	it("буферизация запрошенного воспроизведения тоже пауза", () => {
		expect(
			shouldPauseOnToggle(
				toggleState({ buffering: true, desiredPlaying: true }),
			),
		).toBe(true);
	});

	it("буферизация без намерения играть не блокирует play", () => {
		expect(shouldPauseOnToggle(toggleState({ buffering: true }))).toBe(false);
	});
});

describe("audio playback track-change policy", () => {
	it("буферизация при next/prev не ставит на паузу", () => {
		expect(
			wasPlayingBeforeChange(
				toggleState({ buffering: true, desiredPlaying: true }),
			),
		).toBe(true);
	});

	it("загрузка с намерением играть продолжает играть", () => {
		expect(
			wasPlayingBeforeChange(
				toggleState({ loading: true, desiredPlaying: true }),
			),
		).toBe(true);
	});

	it("внешняя пауза не запускает следующий трек", () => {
		expect(
			wasPlayingBeforeChange(
				toggleState({
					playing: false,
					loading: false,
					buffering: false,
					desiredPlaying: true,
				}),
			),
		).toBe(false);
	});

	it("внешняя пауза во время буферизации гасит stale desired", () => {
		const desired = desiredAfterStatus({
			playing: false,
			loading: false,
			buffering: true,
			timeControlStatus: "paused",
			desiredPlaying: true,
		});
		expect(desired).toBe(false);
		expect(
			wasPlayingBeforeChange(
				toggleState({ buffering: true, desiredPlaying: desired }),
			),
		).toBe(false);
	});

	it("конец трека продолжает звук, даже если status уже playing=false", () => {
		expect(shouldResumeAfterTrackChange(false, true)).toBe(true);
		expect(shouldResumeAfterTrackChange(true, true)).toBe(true);
	});

	it("ручной next/prev продолжает только игравший трек", () => {
		expect(shouldResumeAfterTrackChange(true, false)).toBe(true);
		expect(shouldResumeAfterTrackChange(false, false)).toBe(false);
	});
});

describe("audio playback status intent", () => {
	it("playing подтверждает намерение", () => {
		expect(
			desiredAfterStatus({
				playing: true,
				loading: false,
				buffering: false,
				timeControlStatus: "playing",
				desiredPlaying: false,
			}),
		).toBe(true);
	});

	it("paused сбрасывает stale намерение", () => {
		expect(
			desiredAfterStatus({
				playing: false,
				loading: false,
				buffering: false,
				timeControlStatus: "paused",
				desiredPlaying: true,
			}),
		).toBe(false);
	});

	it("ожидание буферизации сохраняет намерение играть", () => {
		expect(
			desiredAfterStatus({
				playing: false,
				loading: false,
				buffering: true,
				// biome-ignore lint/security/noSecrets: значение status из expo-audio.
				timeControlStatus: "waitingToPlayAtSpecifiedRate",
				desiredPlaying: true,
			}),
		).toBe(true);
	});

	it("во время загрузки источника намерение не меняется", () => {
		expect(
			desiredAfterStatus({
				playing: false,
				loading: true,
				buffering: false,
				timeControlStatus: "paused",
				desiredPlaying: true,
			}),
		).toBe(true);
	});
});
