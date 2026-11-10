import { describe, expect, it } from "vitest";
import {
	buildProgressPayload,
	isCompleted,
	type ProgressDeleteGate,
	type ProgressSaveGate,
	RESET_POSITION_SECONDS,
	resumePosition,
	SAVE_INTERVAL_MS,
	shouldDeleteProgress,
	shouldSaveProgress,
} from "./videoProgress";

function gate(overrides: Partial<ProgressSaveGate> = {}): ProgressSaveGate {
	return {
		position: 30,
		duration: 100,
		now: 10_000,
		lastSavedAt: null,
		lastSavedPosition: -1,
		...overrides,
	};
}

describe("isCompleted", () => {
	it("завершает просмотр ровно с 90%", () => {
		expect(isCompleted(89.9, 100)).toBe(false);
		expect(isCompleted(90, 100)).toBe(true);
		expect(isCompleted(90.1, 100)).toBe(true);
		expect(isCompleted(9, 10)).toBe(true);
		// 0.9*duration не должно давать ложный промах из-за floating point.
		expect(isCompleted(11.7, 13)).toBe(true);
	});

	it("не считает завершённым без длительности и для отрицательной позиции", () => {
		expect(isCompleted(30, 0)).toBe(false);
		expect(isCompleted(30, Number.NaN)).toBe(false);
		expect(isCompleted(-5, 100)).toBe(false);
	});
});

describe("shouldSaveProgress", () => {
	it("сохраняет первое измерение и не ждёт интервал", () => {
		expect(shouldSaveProgress(gate())).toBe(true);
	});

	it("троттлит PUT до SAVE_INTERVAL_MS воспроизведения", () => {
		const savedAt = 1_000;
		expect(
			shouldSaveProgress(
				gate({ lastSavedAt: savedAt, now: savedAt + SAVE_INTERVAL_MS - 1 }),
			),
		).toBe(false);
		expect(
			shouldSaveProgress(
				gate({ lastSavedAt: savedAt, now: savedAt + SAVE_INTERVAL_MS }),
			),
		).toBe(true);
	});

	it("pause/unmount/end игнорируют интервал, но не дублируют секунду", () => {
		expect(
			shouldSaveProgress(
				gate({ force: true, lastSavedAt: 9_500, now: 10_000 }),
			),
		).toBe(true);
		expect(
			shouldSaveProgress(
				gate({ force: true, lastSavedPosition: 30, lastSavedAt: 9_500 }),
			),
		).toBe(false);
	});

	it("сравнивает позиции в целых секундах", () => {
		expect(
			shouldSaveProgress(
				gate({ position: 30.9, lastSavedPosition: 30, lastSavedAt: null }),
			),
		).toBe(false);
	});

	it("не сохраняет 0, неизвестную длительность и позицию за концом", () => {
		expect(shouldSaveProgress(gate({ position: 0 }))).toBe(false);
		expect(shouldSaveProgress(gate({ position: -3 }))).toBe(false);
		expect(shouldSaveProgress(gate({ duration: 0 }))).toBe(false);
		expect(shouldSaveProgress(gate({ duration: Number.NaN }))).toBe(false);
		expect(shouldSaveProgress(gate({ position: 150, duration: 100 }))).toBe(
			false,
		);
	});

	it("после end не перезаписывает финальную позицию нулём", () => {
		expect(shouldSaveProgress(gate({ position: 0, ended: true }))).toBe(false);
		expect(shouldSaveProgress(gate({ position: 100, ended: true }))).toBe(
			false,
		);
		// Сам end сохраняет принудительно и с новой позицией.
		expect(
			shouldSaveProgress(gate({ position: 100, ended: true, force: true })),
		).toBe(true);
	});
});

describe("shouldDeleteProgress", () => {
	function deleteGate(
		overrides: Partial<ProgressDeleteGate> = {},
	): ProgressDeleteGate {
		return {
			position: 0,
			playedOnce: true,
			wasAwayFromStart: true,
			...overrides,
		};
	}

	it("удаляет 0 после реального playback", () => {
		expect(shouldDeleteProgress(deleteGate())).toBe(true);
		expect(
			shouldDeleteProgress(deleteGate({ position: RESET_POSITION_SECONDS })),
		).toBe(true);
	});

	it("не удаляет 0 до старта или на обычном старте с начала", () => {
		expect(shouldDeleteProgress(deleteGate({ playedOnce: false }))).toBe(false);
		expect(shouldDeleteProgress(deleteGate({ wasAwayFromStart: false }))).toBe(
			false,
		);
	});

	it("не трогает запись дальше порога и после end", () => {
		expect(
			shouldDeleteProgress(
				deleteGate({ position: RESET_POSITION_SECONDS + 0.01 }),
			),
		).toBe(false);
		expect(shouldDeleteProgress(deleteGate({ ended: true }))).toBe(false);
		expect(shouldDeleteProgress(deleteGate({ alreadyDeleted: true }))).toBe(
			false,
		);
	});
});

describe("resumePosition", () => {
	const progress = { position: 30, duration: 100, completed: false };
	const context = { duration: 100, currentPosition: 0, hasStarted: false };

	it("404 → null: отсутствие записи не даёт resume", () => {
		expect(resumePosition(null, context)).toBeNull();
	});

	it("не продолжает завершённый просмотр и нулевую позицию", () => {
		expect(
			resumePosition({ ...progress, completed: true }, context),
		).toBeNull();
		expect(resumePosition({ ...progress, position: 0 }, context)).toBeNull();
	});

	it("не трогает плеер, если пользователь уже начал или позиция восстановлена после 401", () => {
		expect(
			resumePosition(progress, { ...context, hasStarted: true }),
		).toBeNull();
		expect(
			resumePosition(progress, { ...context, currentPosition: 5 }),
		).toBeNull();
		// Небольшой дрейф источника resume не отменяет.
		expect(resumePosition(progress, { ...context, currentPosition: 0.5 })).toBe(
			30,
		);
	});

	it("возвращает позицию до порога 90% и не продолжает с 90%", () => {
		expect(resumePosition({ ...progress, position: 89.9 }, context)).toBe(89.9);
		expect(resumePosition({ ...progress, position: 90 }, context)).toBeNull();
	});

	it("использует серверную длительность, если плеер её ещё не знает", () => {
		expect(resumePosition(progress, { ...context, duration: 0 })).toBe(30);
		expect(
			resumePosition({ ...progress, duration: 0 }, { ...context, duration: 0 }),
		).toBeNull();
	});

	it("клампет позицию за концом и не продолжает с конца", () => {
		expect(
			resumePosition(
				{ ...progress, position: 150 },
				{ ...context, duration: 100 },
			),
		).toBeNull();
	});
});

describe("buildProgressPayload", () => {
	it("отдаёт целые секунды и completed по порогу 90%", () => {
		expect(buildProgressPayload(7, 30.7, 100.9)).toEqual({
			mediaId: 7,
			position: 30,
			duration: 100,
			completed: false,
		});
		expect(buildProgressPayload(7, 90.2, 100)).toEqual({
			mediaId: 7,
			position: 90,
			duration: 100,
			completed: true,
		});
	});

	it("зажимает позицию в длительность и чистит мусор", () => {
		expect(buildProgressPayload(7, 150, 100)).toEqual({
			mediaId: 7,
			position: 100,
			duration: 100,
			completed: true,
		});
		expect(buildProgressPayload(7, -5, 100)).toMatchObject({
			position: 0,
			completed: false,
		});
		expect(buildProgressPayload(7, 10, Number.NaN)).toEqual({
			mediaId: 7,
			position: 10,
			duration: 0,
			completed: false,
		});
	});
});
