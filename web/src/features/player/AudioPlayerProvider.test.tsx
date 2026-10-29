import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook } from "@testing-library/react";
import type { ReactNode } from "react";
import {
	afterEach,
	beforeAll,
	beforeEach,
	describe,
	expect,
	it,
	vi,
} from "vitest";
import type { Media } from "../../core/media";
import { AudioPlayerProvider, useAudioPlayer } from "./AudioPlayerProvider";

function media(id: number, title: string): Media {
	return {
		id,
		title,
		filename: `${id}.mp3`,
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 180,
		width: 0,
		height: 0,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
	};
}

// jsdom не умеет воспроизводить: заглушки, чтобы провайдер не падал
// на play/pause/load скрытого <audio>.
beforeAll(() => {
	vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
	vi.spyOn(HTMLMediaElement.prototype, "pause").mockImplementation(() => {});
	vi.spyOn(HTMLMediaElement.prototype, "load").mockImplementation(() => {});
});

beforeEach(() => {
	vi.stubGlobal(
		"fetch",
		vi.fn(() =>
			Promise.resolve(
				new Response(JSON.stringify({ error: "not found" }), {
					status: 404,
					headers: { "Content-Type": "application/json" },
				}),
			),
		),
	);
});

afterEach(() => {
	vi.unstubAllGlobals();
});

function setup() {
	const client = new QueryClient({
		defaultOptions: {
			queries: { retry: false },
			mutations: { retry: false },
		},
	});
	const wrapper = ({ children }: { children: ReactNode }) => (
		<QueryClientProvider client={client}>
			<AudioPlayerProvider>{children}</AudioPlayerProvider>
		</QueryClientProvider>
	);
	return renderHook(() => useAudioPlayer(), { wrapper });
}

describe("AudioPlayerProvider", () => {
	it("ставит трек по индексу и ходит по очереди", () => {
		const { result } = setup();
		act(() => {
			result.current.playQueue(
				[media(1, "Первый"), media(2, "Второй"), media(3, "Третий")],
				1,
			);
		});
		expect(result.current.current?.id).toBe(2);
		expect(result.current.index).toBe(1);

		act(() => result.current.next());
		expect(result.current.current?.id).toBe(3);

		// Конец очереди: дальше некуда, текущий трек не меняется.
		act(() => result.current.next());
		expect(result.current.current?.id).toBe(3);

		act(() => result.current.previous());
		expect(result.current.current?.id).toBe(2);
	});

	it("не выходит за границы очереди при выборе", () => {
		const { result } = setup();
		act(() => result.current.playQueue([media(1, "Первый")], 0));
		act(() => result.current.select(5));
		expect(result.current.current?.id).toBe(1);
		act(() => result.current.select(-1));
		expect(result.current.current?.id).toBe(1);
	});

	it("удаление трека выше текущего сдвигает индекс", () => {
		const { result } = setup();
		act(() => {
			result.current.playQueue(
				[media(1, "Первый"), media(2, "Второй"), media(3, "Третий")],
				1,
			);
		});
		act(() => result.current.removeAt(0));
		expect(result.current.queue.map((item) => item.id)).toEqual([2, 3]);
		expect(result.current.index).toBe(0);
		expect(result.current.current?.id).toBe(2);
	});

	it("удаление последнего трека очищает плеер", () => {
		const { result } = setup();
		act(() => result.current.playMedia(media(1, "Первый")));
		expect(result.current.current?.id).toBe(1);
		act(() => result.current.removeAt(0));
		expect(result.current.queue).toEqual([]);
		expect(result.current.current).toBeNull();
	});

	it("clear сбрасывает очередь", () => {
		const { result } = setup();
		act(() => result.current.playMedia(media(1, "Первый")));
		act(() => result.current.clear());
		expect(result.current.queue).toEqual([]);
		expect(result.current.current).toBeNull();
		expect(result.current.currentTime).toBe(0);
	});

	it("пустой список не запускает воспроизведение", () => {
		const { result } = setup();
		act(() => result.current.playQueue([], 0));
		expect(result.current.queue).toEqual([]);
		expect(result.current.current).toBeNull();
	});

	it("громкость ограничена диапазоном 0…1", () => {
		const { result } = setup();
		act(() => result.current.setVolume(2));
		expect(result.current.volume).toBe(1);
		act(() => result.current.setVolume(-0.5));
		expect(result.current.volume).toBe(0);
	});
});
