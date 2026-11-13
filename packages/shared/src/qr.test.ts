import { describe, expect, it } from "vitest";
import { qrMatrix } from "./qr";

describe("qrMatrix", () => {
	it("returns a square matrix and is deterministic", () => {
		const first = qrMatrix("https://example.com/activate");
		const second = qrMatrix("https://example.com/activate");
		expect(first.size).toBeGreaterThan(0);
		expect(first.cells).toHaveLength(first.size * first.size);
		expect(first).toEqual(second);
	});

	it("changes with content", () => {
		const a = qrMatrix("https://flux.example.com/activate?code=AAAA");
		const b = qrMatrix("https://flux.example.com/activate?code=BBBB");
		expect(a.cells).not.toEqual(b.cells);
	});
});
