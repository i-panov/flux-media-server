import { fireEvent, render, renderHook, screen } from "@testing-library/react";
import { act } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { TVModeProvider } from "./TVModeContext";
import { TV_MODE_STORAGE_KEY } from "./tvMode";
import { type TVModeState, useTVMode } from "./useTVMode";

const routerSearch = vi.hoisted(() => ({ value: "" }));
const historyReplace = vi.hoisted(() => vi.fn());

vi.mock("@tanstack/react-router", () => ({
	useRouterState: (options: {
		select: (state: { location: { searchStr: string } }) => string;
	}): string => options.select({ location: { searchStr: routerSearch.value } }),
	useRouter: () => ({ history: { replace: historyReplace } }),
}));

afterEach(() => {
	routerSearch.value = "";
	historyReplace.mockClear();
	window.localStorage.clear();
	window.history.replaceState(null, "", "/");
});

function StateProbe({
	id,
	onState,
}: {
	id: number;
	onState: (id: number, state: TVModeState) => void;
}) {
	const state = useTVMode();
	onState(id, state);
	return null;
}

function ToggleProbe() {
	const { tvMode, setTVMode } = useTVMode();
	return (
		<button
			type="button"
			data-testid="tv-toggle"
			onClick={() => setTVMode(!tvMode)}
		>
			{String(tvMode)}
		</button>
	);
}

function ReaderProbe() {
	const { tvMode } = useTVMode();
	return <span data-testid="tv-reader">{String(tvMode)}</span>;
}

describe("useTVMode", () => {
	it("по умолчанию режим выключен", () => {
		const { result } = renderHook(() => useTVMode());
		expect(result.current.tvMode).toBe(false);
	});

	it("?tv=1 включает режим и сохраняет флаг", () => {
		routerSearch.value = "?tv=1";
		const { result } = renderHook(() => useTVMode());
		expect(result.current.tvMode).toBe(true);
		expect(window.localStorage.getItem(TV_MODE_STORAGE_KEY)).toBe("1");
	});

	it("сохранённый флаг включает режим без параметра", () => {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, "1");
		const { result } = renderHook(() => useTVMode());
		expect(result.current.tvMode).toBe(true);
	});

	it("setTVMode переключает и пишет флаг", () => {
		const { result } = renderHook(() => useTVMode());

		act(() => {
			result.current.setTVMode(true);
		});
		expect(result.current.tvMode).toBe(true);
		expect(window.localStorage.getItem(TV_MODE_STORAGE_KEY)).toBe("1");

		act(() => {
			result.current.setTVMode(false);
		});
		expect(result.current.tvMode).toBe(false);
		expect(window.localStorage.getItem(TV_MODE_STORAGE_KEY)).toBe("0");
	});

	it("выключенный тумблер при `?tv=1` остаётся выключенным и после reload", () => {
		window.history.replaceState(null, "", "/settings?tv=1");
		routerSearch.value = "?tv=1";
		const { result, unmount } = renderHook(() => useTVMode());
		expect(result.current.tvMode).toBe(true);

		act(() => {
			result.current.setTVMode(false);
		});

		expect(result.current.tvMode).toBe(false);
		// Эффект больше не переписывает "1", а устаревший параметр убран,
		// иначе reload снова включил бы ТВ.
		expect(window.localStorage.getItem(TV_MODE_STORAGE_KEY)).toBe("0");
		expect(window.location.search).toBe("");

		unmount();
		routerSearch.value = window.location.search;
		const reloaded = renderHook(() => useTVMode());
		expect(reloaded.result.current.tvMode).toBe(false);
		reloaded.unmount();
	});

	it("два инстанса под одним провайдером видят одно состояние", () => {
		const seen: TVModeState[] = [];
		const handleState = (id: number, state: TVModeState) => {
			seen[id] = state;
		};

		render(
			<TVModeProvider>
				<StateProbe id={0} onState={handleState} />
				<StateProbe id={1} onState={handleState} />
			</TVModeProvider>,
		);

		expect(seen[0]?.tvMode).toBe(false);
		expect(seen[1]?.tvMode).toBe(false);

		act(() => {
			seen[0]?.setTVMode(true);
		});

		expect(seen[0]?.tvMode).toBe(true);
		expect(seen[1]?.tvMode).toBe(true);
	});

	it("тумблер в одном месте читается в другом без навигации", () => {
		render(
			<TVModeProvider>
				<ToggleProbe />
				<ReaderProbe />
			</TVModeProvider>,
		);

		expect(screen.getByTestId("tv-reader")).toHaveTextContent("false");
		fireEvent.click(screen.getByTestId("tv-toggle"));
		expect(screen.getByTestId("tv-reader")).toHaveTextContent("true");
	});
});
