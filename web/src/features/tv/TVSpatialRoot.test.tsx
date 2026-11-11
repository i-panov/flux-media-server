import { render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { TVSpatialRoot } from "./TVSpatialRoot";

const spatial = vi.hoisted(() => ({
	init: vi.fn(),
	pause: vi.fn(),
	resume: vi.fn(),
	destroy: vi.fn(),
}));
const mode = vi.hoisted(() => ({ tvMode: true }));

vi.mock("@noriginmedia/norigin-spatial-navigation", () => spatial);
vi.mock("./tvBack", () => ({ useTVBackNavigation: vi.fn() }));
vi.mock("./tvRouteFocus", () => ({ useTVRouteFocus: vi.fn() }));
vi.mock("./useTVMode", () => ({
	useTVMode: () => ({ tvMode: mode.tvMode }),
}));

beforeEach(() => {
	spatial.init.mockClear();
	spatial.pause.mockClear();
	spatial.resume.mockClear();
	spatial.destroy.mockClear();
	mode.tvMode = true;
});

describe("TVSpatialRoot", () => {
	it("off→on не сносит реестр focusable через destroy", () => {
		const { rerender } = render(<TVSpatialRoot />);
		expect(spatial.init).toHaveBeenCalledWith({ shouldFocusDOMNode: true });
		expect(spatial.resume).toHaveBeenCalled();

		mode.tvMode = false;
		rerender(<TVSpatialRoot />);
		expect(spatial.pause).toHaveBeenCalled();

		mode.tvMode = true;
		rerender(<TVSpatialRoot />);
		expect(spatial.resume).toHaveBeenCalled();
		expect(spatial.destroy).not.toHaveBeenCalled();
	});
});
