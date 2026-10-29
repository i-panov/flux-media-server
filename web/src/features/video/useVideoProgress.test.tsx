import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useVideoProgress } from "./useVideoProgress";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function progressBody(mediaId: number, position: number, duration = 3600) {
	return {
		id: 1,
		user_id: 1,
		media_id: mediaId,
		position,
		duration,
		completed: false,
		updated_at: "2026-01-01T00:00:00Z",
	};
}

// Фейковый <video>: хуку нужны только currentTime и duration.
function fakeVideo(currentTime = 0, duration = 3600): HTMLVideoElement {
	return { currentTime, duration } as HTMLVideoElement;
}

// Один клиент на файл: кэш между тестами очищается в afterEach.
const testClient = new QueryClient({
	defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
});

function TestWrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={testClient}>{children}</QueryClientProvider>
	);
}

function putCalls(fetchMock: ReturnType<typeof vi.fn>) {
	return fetchMock.mock.calls.filter(
		([, init]) => (init as RequestInit | undefined)?.method === "PUT",
	);
}

function lastPutBody(fetchMock: ReturnType<typeof vi.fn>): {
	position: number;
	duration: number;
	completed: boolean;
} {
	const puts = putCalls(fetchMock);
	const last = puts.at(-1);
	if (last === undefined) {
		throw new Error("PUT не был отправлен");
	}
	const body: unknown = (last[1] as RequestInit).body;
	if (typeof body !== "string") {
		throw new Error("PUT без тела");
	}
	return JSON.parse(body) as {
		position: number;
		duration: number;
		completed: boolean;
	};
}

afterEach(() => {
	testClient.clear();
	vi.unstubAllGlobals();
});

describe("useVideoProgress", () => {
	it("не восстанавливает позицию до прихода данных прогресса", async () => {
		let resolveProgress: ((response: Response) => void) | null = null;
		const fetchMock = vi.fn().mockImplementation((url: string) => {
			if (String(url).includes("/progress/")) {
				return new Promise<Response>((resolve) => {
					resolveProgress = resolve;
				});
			}
			return Promise.resolve(jsonResponse({}));
		});
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});

		result.current.handleLoadedMetadata();
		expect(video.currentTime).toBe(0);

		(resolveProgress as unknown as (response: Response) => void)(
			jsonResponse(progressBody(7, 120)),
		);
		await waitFor(() => {
			expect(video.currentTime).toBe(120);
		});
	});

	it("восстанавливает позицию, когда прогресс пришёл раньше метаданных", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 90)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});

		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		// Метаданные приходят после данных: восстановление обязано сработать.
		result.current.handleLoadedMetadata();
		await waitFor(() => {
			expect(video.currentTime).toBe(90);
		});
	});

	it("не трогает позицию, если пользователь уже начал смотреть", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 300)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(42, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});

		result.current.handleLoadedMetadata();
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		expect(video.currentTime).toBe(42);
	});

	it("не ходит за прогрессом при невалидном mediaId", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({}));
		vi.stubGlobal("fetch", fetchMock);

		const ref = { current: fakeVideo() };
		renderHook(() => useVideoProgress(Number.NaN, ref, false), {
			wrapper: TestWrapper,
		});

		await new Promise((resolve) => setTimeout(resolve, 20));
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it("сохраняет позицию не чаще, чем раз в 10 секунд", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 0)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		// Между отметками 10 с — PUT не должен уходить на каждый тик.
		for (const time of [1, 2, 5, 9]) {
			video.currentTime = time;
			result.current.handleTimeUpdate();
		}
		expect(putCalls(fetchMock).length).toBe(0);

		video.currentTime = 10;
		result.current.handleTimeUpdate();
		await waitFor(() => {
			expect(putCalls(fetchMock).length).toBe(1);
		});

		// pause сохраняет последнюю позицию поверх каденции.
		video.currentTime = 12;
		result.current.handlePause();
		await waitFor(() => {
			expect(putCalls(fetchMock).length).toBe(2);
		});

		const body = lastPutBody(fetchMock);
		expect(body.position).toBe(12);
		expect(body.duration).toBe(3600);
		expect(body.completed).toBe(false);
	});

	it("помечает просмотр завершённым у конца файла", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 0)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 100);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		video.currentTime = 98;
		result.current.handlePause();

		await waitFor(() => {
			expect(putCalls(fetchMock).length).toBe(1);
		});
		const body = lastPutBody(fetchMock);
		expect(body.position).toBe(98);
		expect(body.completed).toBe(true);
	});

	it("при 404 не восстанавливает позицию и не считает это ошибкой", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "Progress not found" }, 404));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useVideoProgress(7, ref), {
			wrapper: TestWrapper,
		});

		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		result.current.handleLoadedMetadata();
		await new Promise((resolve) => setTimeout(resolve, 20));
		expect(video.currentTime).toBe(0);
		expect(putCalls(fetchMock).length).toBe(0);
	});

	it("сохраняет позицию под прежним id при смене mediaId", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 0)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result, rerender } = renderHook(
			({ mediaId }) => useVideoProgress(mediaId, ref),
			{ wrapper: TestWrapper, initialProps: { mediaId: 7 } },
		);
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		video.currentTime = 55;
		result.current.handleTimeUpdate();

		// Переход /video/7 → /video/8 без размонтирования: элемент уже новый.
		rerender({ mediaId: 8 });

		await waitFor(() => {
			expect(putCalls(fetchMock).length).toBe(1);
		});
		const puts = putCalls(fetchMock);
		const first = puts[0];
		if (first === undefined) {
			throw new Error("PUT не был отправлен");
		}
		expect(String(first[0])).toContain("/progress/7");
		expect((first[1] as RequestInit).body).toBeTypeOf("string");
		expect(lastPutBody(fetchMock).position).toBe(55);
	});
});
