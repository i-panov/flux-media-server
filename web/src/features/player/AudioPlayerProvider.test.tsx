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
import { QUEUE_STORAGE_KEY } from "./playerPersistence";

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
	localStorage.clear();
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

	it("переключает перемешивание и циклит режим повтора", () => {
		const { result } = setup();
		expect(result.current.shuffle).toBe(false);
		expect(result.current.repeat).toBe("off");
		act(() => result.current.toggleShuffle());
		expect(result.current.shuffle).toBe(true);
		act(() => result.current.cycleRepeat());
		expect(result.current.repeat).toBe("all");
		act(() => result.current.cycleRepeat());
		expect(result.current.repeat).toBe("one");
		act(() => result.current.cycleRepeat());
		expect(result.current.repeat).toBe("off");
	});

	it("повтор очереди зацикливает next на первом треке", () => {
		const { result } = setup();
		act(() => {
			result.current.playQueue([media(1, "Первый"), media(2, "Второй")], 1);
		});
		act(() => result.current.cycleRepeat());
		act(() => result.current.next());
		expect(result.current.current?.id).toBe(1);
	});

	it("previous зацикливается на последний трек при повторе очереди", () => {
		const { result } = setup();
		act(() => {
			result.current.playQueue(
				[media(1, "Первый"), media(2, "Второй"), media(3, "Третий")],
				0,
			);
		});
		act(() => result.current.previous());
		expect(result.current.current?.id).toBe(1);
		act(() => result.current.cycleRepeat());
		act(() => result.current.previous());
		expect(result.current.current?.id).toBe(3);
	});

	it("перемешанная очередь останавливается без повтора", () => {
		const { result } = setup();
		act(() => {
			result.current.playQueue([media(1, "Первый"), media(2, "Второй")], 0);
		});
		act(() => result.current.toggleShuffle());
		act(() => result.current.next());
		expect(result.current.current?.id).toBe(2);
		// Всё сыграно: дальше — стоп, а не случайный повтор.
		act(() => result.current.next());
		expect(result.current.current?.id).toBe(2);
	});

	it("сохраняет очередь и поднимает её после перезамонтирования", () => {
		const first = setup();
		act(() => {
			first.result.current.playQueue(
				[media(1, "Первый"), media(2, "Второй")],
				1,
			);
		});
		act(() => first.result.current.setVolume(0.5));
		act(() => first.result.current.toggleShuffle());
		first.unmount();

		const second = setup();
		expect(second.result.current.queue.map((item) => item.id)).toEqual([1, 2]);
		expect(second.result.current.index).toBe(1);
		expect(second.result.current.current?.id).toBe(2);
		expect(second.result.current.volume).toBe(0.5);
		expect(second.result.current.shuffle).toBe(true);
		// Автоплей не восстанавливаем: браузеры его режут, старт — по кнопке.
		expect(second.result.current.playing).toBe(false);
	});

	it("clear стирает сохранённую очередь", () => {
		const first = setup();
		act(() => first.result.current.playMedia(media(1, "Первый")));
		act(() => first.result.current.clear());
		first.unmount();

		const second = setup();
		expect(second.result.current.queue).toEqual([]);
		expect(second.result.current.current).toBeNull();
	});

	it("clear оставляет громкость и режимы", () => {
		const first = setup();
		act(() => first.result.current.playMedia(media(1, "Первый")));
		act(() => first.result.current.setVolume(0.5));
		act(() => first.result.current.toggleShuffle());
		act(() => first.result.current.clear());
		first.unmount();

		const second = setup();
		expect(second.result.current.queue).toEqual([]);
		expect(second.result.current.volume).toBe(0.5);
		expect(second.result.current.shuffle).toBe(true);
	});

	it("shuffle не повторяет сыгранное после перезамонтирования", () => {
		const first = setup();
		act(() => {
			first.result.current.playQueue(
				[media(1, "Первый"), media(2, "Второй"), media(3, "Третий")],
				0,
			);
		});
		act(() => first.result.current.toggleShuffle());
		act(() => first.result.current.next());
		const secondId = first.result.current.current?.id;
		first.unmount();

		const second = setup();
		expect(second.result.current.current?.id).toBe(secondId);
		act(() => second.result.current.next());
		const thirdId = second.result.current.current?.id;
		// Все три трека разные: сыгранное до перезагрузки не повторилось.
		expect(new Set([1, secondId, thirdId]).size).toBe(3);
		// Всё сыграно: дальше — стоп.
		act(() => second.result.current.next());
		expect(second.result.current.current?.id).toBe(thirdId);
	});

	it("битое хранилище не ломает плеер", () => {
		localStorage.setItem(QUEUE_STORAGE_KEY, "not json");
		const { result } = setup();
		expect(result.current.queue).toEqual([]);
		expect(result.current.current).toBeNull();
	});
});
