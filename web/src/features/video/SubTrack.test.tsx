import { fireEvent, render } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SubTrack } from "./VideoDetailPage";

describe("SubTrack", () => {
	it("пробрасывает ошибку загрузки дорожки в onError", () => {
		const onError = vi.fn();
		render(
			<SubTrack
				base="ru"
				label="ru"
				url="/api/media/1/subs/ru"
				onError={onError}
			/>,
		);

		const track = document.querySelector("track");
		if (track === null) {
			throw new Error("expected track element");
		}
		fireEvent.error(track);

		expect(onError).toHaveBeenCalledTimes(1);
	});

	it("снимает слушатель при размонтировании", () => {
		const onError = vi.fn();
		const { unmount } = render(
			<SubTrack
				base="ru"
				label="ru"
				url="/api/media/1/subs/ru"
				onError={onError}
			/>,
		);

		const track = document.querySelector("track");
		if (track === null) {
			throw new Error("expected track element");
		}
		unmount();
		track.dispatchEvent(new Event("error"));

		expect(onError).not.toHaveBeenCalled();
	});
});
