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

	it("503 — нет ffmpeg, 429 — очередь переполнена", () => {
		expect(classifyExtractError(new ApiError(503, "no ffmpeg")).kind).toBe(
			"unavailable",
		);
		expect(classifyExtractError(new ApiError(429, "full")).kind).toBe(
			"queueFull",
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
