import { describe, expect, it } from "vitest";
import {
	audioResumeTarget,
	shouldApplyResume,
	shouldPreemptResumeOn401,
} from "./audioProgress";
import { buildProgressPayload } from "./videoProgress";

const progress = {
	position: 42,
	duration: 180,
	completed: false,
};

describe("audio resume target", () => {
	it("возвращает сохранённую позицию после loaded", () => {
		expect(
			audioResumeTarget(progress, {
				duration: 180,
				currentPosition: 0,
				hasStarted: false,
			}),
		).toBe(42);
	});

	it("не перематывает, если пользователь уже начал слушать", () => {
		expect(
			audioResumeTarget(progress, {
				duration: 180,
				currentPosition: 5,
				hasStarted: true,
			}),
		).toBeNull();
	});

	it("завершённый трек начинается заново", () => {
		expect(
			audioResumeTarget(
				{ ...progress, completed: true },
				{ duration: 180, currentPosition: 0, hasStarted: false },
			),
		).toBeNull();
	});
});

describe("shouldApplyResume", () => {
	it("ручной выбор трека/play не мешает resume", () => {
		// Воспроизведение после replace — не действие пользователя.
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: false,
				preempted: false,
				progress,
			}),
		).toBe(true);
	});

	it("seek до запроса отменяет resume", () => {
		expect(
			shouldApplyResume({
				userStartedBefore: true,
				userStartedAfter: true,
				preempted: false,
				progress,
			}),
		).toBe(false);
	});

	it("seek во время запроса отменяет resume", () => {
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: true,
				preempted: false,
				progress,
			}),
		).toBe(false);
	});

	it("401@0 не отключает resume", () => {
		const preempted = shouldPreemptResumeOn401(0);
		expect(preempted).toBe(false);
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: false,
				preempted,
				progress,
			}),
		).toBe(true);
	});

	it("401@>0 отдаёт seek 401-ветке", () => {
		const preempted = shouldPreemptResumeOn401(12);
		expect(preempted).toBe(true);
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: false,
				preempted,
				progress,
			}),
		).toBe(false);
	});

	it("401-preemption отменяет server resume", () => {
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: false,
				preempted: true,
				progress,
			}),
		).toBe(false);
	});

	it("без сохранённого прогресса resume не нужен", () => {
		expect(
			shouldApplyResume({
				userStartedBefore: false,
				userStartedAfter: false,
				preempted: false,
				progress: null,
			}),
		).toBe(false);
	});
});

describe("audio progress payload", () => {
	it("использует общий порог completed 90%", () => {
		expect(buildProgressPayload(9, 161, 180).completed).toBe(false);
		expect(buildProgressPayload(9, 162, 180).completed).toBe(true);
	});
});
