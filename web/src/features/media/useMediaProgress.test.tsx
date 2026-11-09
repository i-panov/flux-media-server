import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useMediaProgress } from "./useMediaProgress";

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

// Фейковый медиаэлемент: хуку нужны только currentTime и duration.
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

function deleteCalls(fetchMock: ReturnType<typeof vi.fn>) {
	return fetchMock.mock.calls.filter(
		([, init]) => (init as RequestInit | undefined)?.method === "DELETE",
	);
}

afterEach(() => {
	testClient.clear();
	vi.unstubAllGlobals();
});

describe("useMediaProgress", () => {
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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});

		act(() => {
			result.current.handleLoadedMetadata();
		});
		expect(video.currentTime).toBe(0);

		// Клиент резолвит транспорт асинхронно: fetch вызывается не позже,
		// чем на первом микротаске после подписки.
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});

		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		// Метаданные приходят после данных: восстановление обязано сработать.
		act(() => {
			result.current.handleLoadedMetadata();
		});
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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});

		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		expect(video.currentTime).toBe(42);
	});

	it("восстанавливает позицию поверх дрейфа автоплея", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 120)));
		vi.stubGlobal("fetch", fetchMock);

		// Автоплей успел уйти на доли секунды раньше данных прогресса.
		const video = fakeVideo(0.5, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useMediaProgress(7, ref, true, 2), {
			wrapper: TestWrapper,
		});

		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(video.currentTime).toBe(120);
		});
	});

	it("без допуска ручной старт не перекрывается позицией", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 300)));
		vi.stubGlobal("fetch", fetchMock);

		// Видео без автоплея: пользователь сам нажал play до прихода
		// данных — прыгать на сохранённую минуту нельзя.
		const video = fakeVideo(1.5, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});

		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		await new Promise((resolve) => setTimeout(resolve, 20));
		expect(video.currentTime).toBe(1.5);
	});

	it("не ходит за прогрессом при невалидном mediaId", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({}));
		vi.stubGlobal("fetch", fetchMock);

		const ref = { current: fakeVideo() };
		renderHook(() => useMediaProgress(Number.NaN, ref, false), {
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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		// Между отметками 10 с — PUT не должен уходить на каждый тик.
		for (const time of [1, 2, 5, 9]) {
			video.currentTime = time;
			act(() => {
				result.current.handleTimeUpdate();
			});
		}
		expect(putCalls(fetchMock).length).toBe(0);

		video.currentTime = 10;
		act(() => {
			result.current.handleTimeUpdate();
		});
		await waitFor(() => {
			expect(putCalls(fetchMock).length).toBe(1);
		});

		// pause сохраняет последнюю позицию поверх каденции.
		video.currentTime = 12;
		act(() => {
			result.current.handlePause();
		});
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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		video.currentTime = 98;
		act(() => {
			result.current.handlePause();
		});

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
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});

		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		act(() => {
			result.current.handleLoadedMetadata();
		});
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
			({ mediaId }) => useMediaProgress(mediaId, ref),
			{ wrapper: TestWrapper, initialProps: { mediaId: 7 } },
		);
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		video.currentTime = 55;
		act(() => {
			result.current.handleTimeUpdate();
		});

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

	it("восстанавливает позицию нового трека после смены mediaId", async () => {
		const fetchMock = vi.fn().mockImplementation((url: string) => {
			const body = String(url).includes("/progress/8")
				? progressBody(8, 40)
				: progressBody(7, 0);
			return Promise.resolve(jsonResponse(body));
		});
		vi.stubGlobal("fetch", fetchMock);

		const first = fakeVideo(0, 3600);
		const ref = { current: first as HTMLVideoElement | null };
		const { result, rerender } = renderHook(
			({ mediaId }) => useMediaProgress(mediaId, ref),
			{ wrapper: TestWrapper, initialProps: { mediaId: 7 } },
		);
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		// Новый элемент нового трека: позиция прошлого сюда не переезжает.
		const second = fakeVideo(0, 3600);
		ref.current = second;
		rerender({ mediaId: 8 });
		act(() => {
			result.current.handleLoadedMetadata();
		});

		await waitFor(() => {
			expect(second.currentTime).toBe(40);
		});
		expect(first.currentTime).toBe(0);
	});

	it("не ставит новому треку позицию прошлого при пустом прогрессе", async () => {
		const fetchMock = vi.fn().mockImplementation((url: string) => {
			if (String(url).includes("/progress/8")) {
				return Promise.resolve(
					jsonResponse({ error: "Progress not found" }, 404),
				);
			}
			return Promise.resolve(jsonResponse(progressBody(7, 120)));
		});
		vi.stubGlobal("fetch", fetchMock);

		const first = fakeVideo(0, 3600);
		const ref = { current: first as HTMLVideoElement | null };
		const { result, rerender } = renderHook(
			({ mediaId }) => useMediaProgress(mediaId, ref),
			{ wrapper: TestWrapper, initialProps: { mediaId: 7 } },
		);
		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(first.currentTime).toBe(120);
		});

		const second = fakeVideo(0, 3600);
		ref.current = second;
		rerender({ mediaId: 8 });
		act(() => {
			result.current.handleLoadedMetadata();
		});
		await act(async () => {
			await new Promise((resolve) => setTimeout(resolve, 30));
		});
		expect(second.currentTime).toBe(0);
	});

	it("сброс в начало удаляет серверный прогресс", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 120)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		// Восстановление ставит сохранённую позицию...
		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(video.currentTime).toBe(120);
		});

		// ...пользователь смотрит (тики времени измеряют ненулевую позицию)...
		video.currentTime = 45;
		act(() => {
			result.current.handleTimeUpdate();
		});

		// ...отматывает в начало и ставит на паузу:
		// вместо PUT уходит DELETE, переоткрытие стартует с 0.
		video.currentTime = 0;
		act(() => {
			result.current.handlePause();
		});
		await waitFor(() => {
			expect(deleteCalls(fetchMock).length).toBe(1);
		});
		const [url] = deleteCalls(fetchMock)[0] as [string, RequestInit];
		expect(String(url)).toContain("/progress/7");
		expect(putCalls(fetchMock).length).toBe(0);
	});

	it("нуль без воспроизведения не удаляет серверный прогресс", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 120)));
		vi.stubGlobal("fetch", fetchMock);

		const video = fakeVideo(0, 3600);
		const ref = { current: video };
		const { result } = renderHook(() => useMediaProgress(7, ref), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});

		// Восстановление ставит сохранённую позицию...
		act(() => {
			result.current.handleLoadedMetadata();
		});
		await waitFor(() => {
			expect(video.currentTime).toBe(120);
		});

		// ...но поток сломался до первого измеренного кадра: элемент так
		// и остался на нуле, ошибка зовёт сохранение — DELETE уходить
		// не должен, иначе восстановленная позиция затёрта не действием
		// пользователя, а сбоем.
		video.currentTime = 0;
		act(() => {
			result.current.handlePause();
		});
		await new Promise((resolve) => setTimeout(resolve, 50));
		expect(deleteCalls(fetchMock).length).toBe(0);
		expect(putCalls(fetchMock).length).toBe(0);
	});
});
