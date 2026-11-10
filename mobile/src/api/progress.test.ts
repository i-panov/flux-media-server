import type { QueryClient } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import {
	continueWatchingQueryKey,
	invalidateContinueWatching,
} from "./progress";

describe("continueWatchingQueryKey", () => {
	it("разделяет продолжение видео и аудио", () => {
		expect(continueWatchingQueryKey("video")).toEqual([
			"progress",
			"continue",
			"video",
		]);
		expect(continueWatchingQueryKey("audio")).toEqual([
			"progress",
			"continue",
			"audio",
		]);
	});
});

describe("invalidateContinueWatching", () => {
	it("инвалидирует ключ продолжения нужного типа", () => {
		const invalidateQueries = vi.fn();
		const client = { invalidateQueries } as unknown as QueryClient;

		invalidateContinueWatching(client, "audio");

		expect(invalidateQueries).toHaveBeenCalledWith({
			queryKey: ["progress", "continue", "audio"],
		});
	});
});
