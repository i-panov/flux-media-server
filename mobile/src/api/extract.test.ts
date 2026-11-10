import { ApiError } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	classifyExtractError,
	classifyExtractStart,
	classifyExtractStatus,
	createCancellableDelay,
	EXTRACT_POLL_INTERVAL_MS,
	MAX_EXTRACT_POLL_FAILURES,
	nextPollFailure,
	phaseAfterStart,
	pollExtractJob,
} from "./extract";

function mediaFixture(overrides: Record<string, unknown> = {}) {
	return {
		id: 9,
		title: "Извлечённый трек",
		filename: "track.m4a",
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
		...overrides,
	};
}

describe("classifyExtractStart", () => {
	it("202 с job_id — это задание, а не готовый трек", () => {
		expect(classifyExtractStart({ job_id: 42 })).toEqual({
			kind: "job",
			jobId: 42,
			alreadyExtracted: false,
		});
	});

	it("200 с Media — дорожка уже существует", () => {
		const result = classifyExtractStart(mediaFixture());
		expect(result.kind).toBe("track");
		if (result.kind !== "track") {
			return;
		}
		expect(result.track.id).toBe(9);
		expect(result.alreadyExtracted).toBe(true);
	});

	it("битый ответ не выдаёт себя за задание", () => {
		expect(() => classifyExtractStart({ job_id: "42" })).toThrow();
		expect(() => classifyExtractStart({})).toThrow();
	});
});

describe("classifyExtractStatus", () => {
	it("читает done вместе с готовым треком", () => {
		const status = classifyExtractStatus({
			id: 3,
			status: "done",
			error: null,
			media: mediaFixture(),
		});
		expect(status.status).toBe("done");
		expect(status.media?.id).toBe(9);
	});

	it("ошибка задания приходит в error", () => {
		const status = classifyExtractStatus({
			id: 3,
			status: "error",
			error: "no audio stream",
		});
		expect(status.status).toBe("error");
		expect(status.error).toBe("no audio stream");
		expect(status.media ?? null).toBeNull();
	});
});

describe("nextPollFailure", () => {
	it("терпит ровно две неудачи подряд и сдаётся на третьей", () => {
		expect(nextPollFailure(0)).toEqual({ failures: 1, giveUp: false });
		expect(nextPollFailure(1)).toEqual({ failures: 2, giveUp: false });
		expect(nextPollFailure(2)).toEqual({
			failures: MAX_EXTRACT_POLL_FAILURES,
			giveUp: true,
		});
	});

	it("после третьей серия продолжает считаться (защита от переполнения)", () => {
		expect(nextPollFailure(MAX_EXTRACT_POLL_FAILURES)).toEqual({
			failures: MAX_EXTRACT_POLL_FAILURES + 1,
			giveUp: true,
		});
	});
});

describe("classifyExtractError", () => {
	it("409 — уже извлечено, а не сетевой сбой", () => {
		expect(classifyExtractError(new ApiError(409, "done")).kind).toBe(
			"conflict",
		);
	});

	it("503 — нет ffmpeg, 429 — общий rate limit", () => {
		expect(classifyExtractError(new ApiError(503, "no ffmpeg")).kind).toBe(
			"unavailable",
		);
		expect(classifyExtractError(new ApiError(429, "full")).kind).toBe(
			"rateLimited",
		);
	});

	it("прочие ошибки — общий сбой с сообщением", () => {
		const failure = classifyExtractError(new Error("network down"));
		expect(failure.kind).toBe("failed");
		expect(failure.message).toBe("network down");
		expect(classifyExtractError(new ApiError(500, "boom")).kind).toBe("failed");
		expect(classifyExtractError(null).kind).toBe("failed");
	});
});

describe("createCancellableDelay", () => {
	it("cancel снимает таймер и сразу резолвит ожидание", async () => {
		expect(EXTRACT_POLL_INTERVAL_MS).toBe(1500);
		const delay = createCancellableDelay();
		let resolved = false;
		const wait = delay.wait(60_000).then(() => {
			resolved = true;
		});
		delay.cancel();
		await wait;
		expect(resolved).toBe(true);
	});
});

describe("phaseAfterStart", () => {
	it("200-трек не оставляет экран в isExtracting", () => {
		expect(phaseAfterStart("track")).toBeNull();
	});

	it("202-задание сразу показывает очередь", () => {
		expect(phaseAfterStart("job")).toBe("queued");
	});
});

describe("pollExtractJob", () => {
	const signal = new AbortController().signal;
	const base = {
		jobId: 7,
		signal,
		onPhase: () => {
			// Фазы проверяются в тестах хука через onPhase, здесь не нужны.
		},
	};

	it("done с media возвращает готовый трек", async () => {
		const result = await pollExtractJob({
			...base,
			isActive: () => true,
			wait: () => Promise.resolve(),
			fetchStatus: () =>
				Promise.resolve({
					id: 7,
					status: "done",
					error: null,
					media: mediaFixture(),
				}),
		});
		expect(result.kind).toBe("done");
		if (result.kind !== "done") {
			return;
		}
		expect(result.result.track.id).toBe(9);
		expect(result.result.alreadyExtracted).toBe(false);
	});

	it("done без media — сбой, а не пустой успех", async () => {
		const result = await pollExtractJob({
			...base,
			isActive: () => true,
			wait: () => Promise.resolve(),
			fetchStatus: () =>
				Promise.resolve({
					id: 7,
					status: "done",
					error: "track deleted",
					media: null,
				}),
		});
		expect(result.kind).toBe("failed");
		if (result.kind !== "failed") {
			return;
		}
		expect(result.failure.kind).toBe("failed");
		expect(result.failure.message).toBe("track deleted");
	});

	it("status=error завершает опрос с сообщением задания", async () => {
		const result = await pollExtractJob({
			...base,
			isActive: () => true,
			wait: () => Promise.resolve(),
			fetchStatus: () =>
				Promise.resolve({
					id: 7,
					status: "error",
					error: "decode failed",
				}),
		});
		expect(result.kind).toBe("failed");
		if (result.kind !== "failed") {
			return;
		}
		expect(result.failure.message).toBe("decode failed");
	});

	it("сдаётся после трёх сетевых ошибок подряд", async () => {
		let calls = 0;
		const result = await pollExtractJob({
			...base,
			isActive: () => true,
			wait: () => Promise.resolve(),
			fetchStatus: () => {
				calls += 1;
				return Promise.reject(new Error("network"));
			},
		});
		expect(result.kind).toBe("failed");
		expect(calls).toBe(MAX_EXTRACT_POLL_FAILURES);
	});

	it("успешный статус сбрасывает серию сбоев", async () => {
		const responses: (() => Promise<unknown>)[] = [
			() => Promise.reject(new Error("network 1")),
			() => Promise.reject(new Error("network 2")),
			() => Promise.resolve({ id: 7, status: "processing" }),
			() => Promise.reject(new Error("network 3")),
			() => Promise.reject(new Error("network 4")),
			() => Promise.resolve({ id: 7, status: "done", media: mediaFixture() }),
		];
		let calls = 0;
		const result = await pollExtractJob({
			...base,
			isActive: () => true,
			wait: () => Promise.resolve(),
			fetchStatus: () => {
				const next = responses[calls];
				calls += 1;
				if (next === undefined) {
					return Promise.reject(new Error("unexpected poll"));
				}
				return next();
			},
		});
		expect(result.kind).toBe("done");
		expect(calls).toBe(responses.length);
	});

	it("отмена до wait не делает ни одного запроса", async () => {
		let waited = false;
		let fetched = false;
		const result = await pollExtractJob({
			...base,
			isActive: () => false,
			wait: () => {
				waited = true;
				return Promise.resolve();
			},
			fetchStatus: () => {
				fetched = true;
				return Promise.reject(new Error("не должно вызываться"));
			},
		});
		expect(result).toEqual({ kind: "cancelled" });
		expect(waited).toBe(false);
		expect(fetched).toBe(false);
	});

	it("отмена во время wait не переходит к запросу", async () => {
		let active = true;
		let fetched = false;
		const result = await pollExtractJob({
			...base,
			isActive: () => active,
			wait: () => {
				active = false;
				return Promise.resolve();
			},
			fetchStatus: () => {
				fetched = true;
				return Promise.reject(new Error("не должно вызываться"));
			},
		});
		expect(result).toEqual({ kind: "cancelled" });
		expect(fetched).toBe(false);
	});
});
