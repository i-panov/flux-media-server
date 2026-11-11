import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { StorageInfo } from "../../api/admin";
import { StorageWidget } from "./StorageWidget";

const storage: StorageInfo = {
	disks: [
		{ path: "/data", total_bytes: 1000, free_bytes: 50, used_bytes: 200 },
	],
	video_bytes: 10,
	audio_bytes: 20,
	originals_bytes: 30,
	temp_bytes: 40,
	auto_cleanup: false,
};

function renderWidget(data: StorageInfo = storage) {
	const queryClient = new QueryClient({
		defaultOptions: { mutations: { retry: false }, queries: { retry: false } },
	});
	const view = render(
		<MantineProvider>
			<QueryClientProvider client={queryClient}>
				<StorageWidget data={data} />
			</QueryClientProvider>
		</MantineProvider>,
	);
	return { ...view, queryClient };
}

function jsonResponse(body: unknown): Response {
	return new Response(JSON.stringify(body), {
		status: 200,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("StorageWidget", () => {
	it("показывает занятое разделом, свободное и общий объём диска", () => {
		renderWidget();

		expect(screen.getByText("Раздел занимает 200 B")).toBeInTheDocument();
		expect(screen.getByText("Свободно на диске 50 B (5%)")).toBeInTheDocument();
		expect(screen.getByText("Всего 1000 B")).toBeInTheDocument();
	});

	it("переключает авточистку и показывает подсказку", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ auto_cleanup: true }));
		vi.stubGlobal("fetch", fetchMock);

		const view = renderWidget();
		const toggle = screen.getByRole("switch", {
			name: "Авточистка оригиналов",
		});
		expect(
			screen.getByText(
				"Удаляет наименее просматриваемые оригиналы при нехватке места",
			),
		).toBeInTheDocument();
		expect(toggle).not.toBeChecked();

		fireEvent.click(toggle);

		await waitFor(() => {
			expect(fetchMock).toHaveBeenCalled();
		});
		const call = fetchMock.mock.calls[0];
		if (call === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(call[0])).toBe("/api/admin/storage/settings");
		expect((call[1] as RequestInit).method).toBe("PUT");
		expect((call[1] as RequestInit).body).toBe(
			JSON.stringify({ auto_cleanup: true }),
		);

		// После инвалидации запрос вернёт новое состояние — Switch
		// управляется данными, а не локальным состоянием.
		view.rerender(
			<MantineProvider>
				<QueryClientProvider client={view.queryClient}>
					<StorageWidget data={{ ...storage, auto_cleanup: true }} />
				</QueryClientProvider>
			</MantineProvider>,
		);
		expect(toggle).toBeChecked();
	});
});
