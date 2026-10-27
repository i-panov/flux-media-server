import { MantineProvider } from "@mantine/core";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { HealthCard } from "./HealthCard";

function renderCard() {
	const queryClient = new QueryClient({
		defaultOptions: { queries: { retry: false } },
	});
	return render(
		<MantineProvider>
			<QueryClientProvider client={queryClient}>
				<HealthCard />
			</QueryClientProvider>
		</MantineProvider>,
	);
}

function okResponse(version: string): Response {
	return new Response(JSON.stringify({ status: "ok", version }), {
		status: 200,
		headers: { "Content-Type": "application/json" },
	});
}

const serverErrorPattern = /Сервер не отвечает/;

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("HealthCard", () => {
	it("показывает статус и версию бэкенда", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(okResponse("1.0.8")));

		renderCard();

		expect(await screen.findByText("1.0.8")).toBeInTheDocument();
		expect(screen.getByText("Онлайн")).toBeInTheDocument();
	});

	it("показывает ошибку, если сервер недоступен", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockRejectedValue(new Error("network is down")),
		);

		renderCard();

		expect(await screen.findByText(serverErrorPattern)).toBeInTheDocument();
		expect(screen.getByText("Недоступен")).toBeInTheDocument();
	});
});
