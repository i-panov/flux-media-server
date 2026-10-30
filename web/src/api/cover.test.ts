import { afterEach, describe, expect, it, vi } from "vitest";
import { uploadCover } from "./cover";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("uploadCover", () => {
	it("отправляет файл полем cover методом PUT", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ cover_url: "/api/media/7/cover" }));
		vi.stubGlobal("fetch", fetchMock);

		const file = new File(["bytes"], "cover.png", { type: "image/png" });
		const url = await uploadCover(7, file);

		expect(fetchMock).toHaveBeenCalledOnce();
		const [path, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(path).toBe("/api/media/7/cover");
		expect(init.method).toBe("PUT");
		const form = init.body as FormData;
		const sent = form.get("cover") as File;
		expect(sent.name).toBe(file.name);
		expect(sent.size).toBe(file.size);
		expect(url).toBe("/api/media/7/cover");
	});

	it("пробрасывает ошибку сервера", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "Cover image too large" }, 413));
		vi.stubGlobal("fetch", fetchMock);

		const file = new File(["bytes"], "cover.png", { type: "image/png" });
		await expect(uploadCover(7, file)).rejects.toThrow("Cover image too large");
	});
});
