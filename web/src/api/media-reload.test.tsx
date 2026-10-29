import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useRef } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useMediaReload, useSavedTime } from "./media";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function videoItem() {
	return {
		id: 7,
		title: "Film 7",
		year: 2024,
		description: "",
		type: "video",
		duration: 60,
		width: 1280,
		height: 720,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function Harness({ id }: { id: number }) {
	const reload = useMediaReload(id);
	return (
		<div>
			<span data-testid="nonce">{reload.nonce}</span>
			<span data-testid="failed">{String(reload.failed)}</span>
			<video
				data-testid="player"
				src={`/api/media/${id}/stream`}
				onError={reload.handleError}
			>
				<track kind="captions" srcLang="ru" label="ru" src="/subs" />
			</video>
			<button type="button" onClick={reload.retry}>
				retry
			</button>
		</div>
	);
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("useMediaReload", () => {
	it("успешный зонд перемонтирует элемент без failed", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(videoItem()));
		vi.stubGlobal("fetch", fetchMock);

		render(<Harness id={7} />);
		fireEvent.error(screen.getByTestId("player"));

		await waitFor(() => {
			expect(screen.getByTestId("nonce")).toHaveTextContent("1");
		});
		expect(screen.getByTestId("failed")).toHaveTextContent("false");
		expect(fetchMock).toHaveBeenCalledWith(
			"/api/media/7",
			expect.objectContaining({ credentials: "same-origin" }),
		);
	});

	it("неудача зонда — failed без повторов", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "gone" }, 404));
		vi.stubGlobal("fetch", fetchMock);

		render(<Harness id={7} />);
		fireEvent.error(screen.getByTestId("player"));

		await waitFor(() => {
			expect(screen.getByTestId("failed")).toHaveTextContent("true");
		});
		fireEvent.error(screen.getByTestId("player"));
		expect(fetchMock).toHaveBeenCalledTimes(1);
		expect(screen.getByTestId("nonce")).toHaveTextContent("0");
	});

	it("retry сбрасывает состояние и пробует снова", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ error: "boom" }, 500))
			.mockResolvedValue(jsonResponse(videoItem()));
		vi.stubGlobal("fetch", fetchMock);

		render(<Harness id={7} />);
		fireEvent.error(screen.getByTestId("player"));

		await waitFor(() => {
			expect(screen.getByTestId("failed")).toHaveTextContent("true");
		});
		fireEvent.click(screen.getByRole("button", { name: "retry" }));
		expect(screen.getByTestId("failed")).toHaveTextContent("false");

		fireEvent.error(screen.getByTestId("player"));
		await waitFor(() => {
			expect(screen.getByTestId("nonce")).toHaveTextContent("2");
		});
		expect(fetchMock).toHaveBeenCalledTimes(2);
	});
});

function PositionHarness() {
	const ref = useRef<HTMLVideoElement | null>(null);
	const position = useSavedTime(ref);
	return (
		<div>
			<video ref={ref} data-testid="player">
				<track kind="captions" srcLang="ru" label="ru" src="/subs" />
			</video>
			<button type="button" onClick={position.save}>
				save position
			</button>
			<button type="button" onClick={position.restore}>
				restore position
			</button>
		</div>
	);
}

describe("useSavedTime", () => {
	function mockCurrentTime(player: HTMLElement, initial: number) {
		let current = initial;
		Object.defineProperty(player, "currentTime", {
			configurable: true,
			get: () => current,
			set: (value: number) => {
				current = value;
			},
		});
		return () => current;
	}

	it("сохраняет позицию и восстанавливает её один раз", () => {
		render(<PositionHarness />);
		const player = screen.getByTestId("player");
		let current = 42;
		let writes = 0;
		Object.defineProperty(player, "currentTime", {
			configurable: true,
			get: () => current,
			set: (value: number) => {
				current = value;
				writes += 1;
			},
		});

		fireEvent.click(screen.getByRole("button", { name: "save position" }));
		current = 0;
		fireEvent.click(screen.getByRole("button", { name: "restore position" }));

		expect(current).toBe(42);
		expect(writes).toBe(1);
		fireEvent.click(screen.getByRole("button", { name: "restore position" }));
		expect(writes).toBe(1);
	});

	it("читает сохранённое значение при восстановлении", () => {
		render(<PositionHarness />);
		const player = screen.getByTestId("player");
		mockCurrentTime(player, 125);

		fireEvent.click(screen.getByRole("button", { name: "save position" }));

		let restored = -1;
		Object.defineProperty(player, "currentTime", {
			configurable: true,
			get: () => restored,
			set: (value: number) => {
				restored = value;
			},
		});
		fireEvent.click(screen.getByRole("button", { name: "restore position" }));

		expect(restored).toBe(125);
	});

	it("не трогает плеер при нулевой сохранённой позиции", () => {
		render(<PositionHarness />);
		const player = screen.getByTestId("player");
		let writes = 0;
		Object.defineProperty(player, "currentTime", {
			configurable: true,
			get: () => 0,
			set: () => {
				writes += 1;
			},
		});

		fireEvent.click(screen.getByRole("button", { name: "restore position" }));

		expect(writes).toBe(0);
	});
});
