import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Media } from "../../core/media";
import { EditMetadataModal } from "./EditMetadataModal";

// Модалка читает ТВ-режим (начальный spatial-фокус), а роутера в тесте
// нет — подменяем строку поиска пустой, как в useTVMode.test.tsx.
vi.mock("@tanstack/react-router", () => ({
	useRouterState: (): string => "",
}));

function mediaItem(): Media {
	return {
		id: 7,
		title: "Исходное название",
		filename: "film.mkv",
		year: 2024,
		description: "",
		type: "video",
		artists: [],
		album: "",
		genre: "",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "https://example.com/source",
		source_media_id: null,
	};
}

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function renderModal(
	onClose: () => void = () => undefined,
	media: Media = mediaItem(),
) {
	const queryClient = new QueryClient({
		defaultOptions: {
			queries: { retry: false },
			mutations: { retry: false },
		},
	});
	const wrapper = ({ children }: { children: ReactNode }) => (
		<MantineProvider>
			<QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
		</MantineProvider>
	);
	return render(<EditMetadataModal opened media={media} onClose={onClose} />, {
		wrapper,
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

beforeEach(() => {
	// Mantine autosize-Textarea слушает document.fonts, которого нет в jsdom.
	if (document.fonts === undefined) {
		Object.defineProperty(document, "fonts", {
			value: {
				addEventListener: vi.fn(),
				removeEventListener: vi.fn(),
			},
			configurable: true,
		});
	}
});

describe("EditMetadataModal", () => {
	it("предзаполняет ссылку из медиа", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ items: [] })),
		);
		renderModal();

		const source =
			await screen.findByLabelText<HTMLInputElement>("Ссылка на источник");
		expect(source.value).toBe("https://example.com/source");
	});

	it("у картинки нет полей года, жанра, альбома и исполнителей", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ items: [] })),
		);
		renderModal(undefined, { ...mediaItem(), type: "image" });

		await screen.findByLabelText("Название");
		expect(screen.queryByLabelText("Год")).toBeNull();
		expect(screen.queryByLabelText("Жанр")).toBeNull();
		expect(screen.queryByLabelText("Альбом")).toBeNull();
		expect(screen.queryByText("Исполнители")).toBeNull();
		expect(screen.queryByLabelText("Ссылка на источник")).toBeNull();
		expect(screen.queryByLabelText("Описание")).toBeNull();
		expect(screen.getByLabelText("Название")).toBeTruthy();
	});

	it("у видео есть год и жанр, но нет альбома и исполнителей", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ items: [] })),
		);
		renderModal();

		await screen.findByLabelText("Название");
		expect(screen.getByLabelText("Год")).toBeTruthy();
		expect(screen.getByLabelText("Жанр")).toBeTruthy();
		expect(screen.queryByLabelText("Альбом")).toBeNull();
		expect(screen.queryByText("Исполнители")).toBeNull();
	});

	it("отмена выбрасывает черновик", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ items: [] })),
		);
		const { unmount } = renderModal();

		const title = await screen.findByLabelText<HTMLInputElement>("Название");
		fireEvent.change(title, { target: { value: "Черновик" } });
		expect(title.value).toBe("Черновик");

		// «Отмена» размонтирует модалку (условный маунт в MediaAdminActions):
		// повторное открытие показывает данные медиа, а не черновик.
		fireEvent.click(screen.getByRole("button", { name: "Отмена" }));
		unmount();
		renderModal();

		const reopened = await screen.findByLabelText<HTMLInputElement>("Название");
		expect(reopened.value).toBe("Исходное название");
	});

	it("при ошибке сети введённое не теряется", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockImplementation((url: string) => {
				if (String(url).includes("/artists")) {
					return Promise.resolve(jsonResponse({ items: [] }));
				}
				return Promise.resolve(jsonResponse({ error: "Invalid year" }, 400));
			}),
		);
		renderModal();

		const title = await screen.findByLabelText<HTMLInputElement>("Название");
		fireEvent.change(title, { target: { value: "Черновик" } });
		fireEvent.click(screen.getByRole("button", { name: "Сохранить" }));

		await waitFor(() => {
			expect(screen.getByText("Не удалось сохранить метаданные")).toBeVisible();
		});
		expect(screen.getByLabelText<HTMLInputElement>("Название").value).toBe(
			"Черновик",
		);
	});
});
