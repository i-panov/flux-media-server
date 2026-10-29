import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CoverImage } from "./CoverImage";

describe("CoverImage", () => {
	it("показывает заглушку без обложки", () => {
		const { container } = render(<CoverImage src="" iconSize={16} />);
		expect(container.querySelector("img")).toBeNull();
	});

	it("после сбоя одной обложки показывает следующую", () => {
		const { container, rerender } = render(
			<CoverImage src="/api/media/1/cover" iconSize={16} />,
		);
		const broken = container.querySelector("img");
		expect(broken).not.toBeNull();
		fireEvent.error(broken as HTMLImageElement);
		expect(container.querySelector("img")).toBeNull();

		// Компонент переиспользуется при смене трека: ошибка прошлого
		// адреса не должна прятать валидную обложку.
		rerender(<CoverImage src="/api/media/2/cover" iconSize={16} />);
		expect(container.querySelector("img")).not.toBeNull();
	});
});
