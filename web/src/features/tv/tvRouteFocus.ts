import {
	getCurrentFocusKey,
	setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { useRouterState } from "@tanstack/react-router";
import { useEffect } from "react";
import {
	TV_FOCUS_KEY_ATTRIBUTE,
	TV_FOCUS_SECONDARY_ATTRIBUTE,
	TV_PAGE_ROOT_ATTRIBUTE,
} from "./tvAttributes";

// Окно доводки фокуса после смены роута. Скелетон/данные приходят
// асинхронно (в тестах — до 2 с), поэтому ждём появления целей, а не
// один фиксированный таймаут.
const FOCUS_WINDOW_MS = 4000;
const MUTATION_DEBOUNCE_MS = 30;

function readCurrentFocusKey(): string | null {
	try {
		const key = getCurrentFocusKey();
		return typeof key === "string" && key !== "" ? key : null;
	} catch {
		// spatial ещё не инициализирован — считаем, что фокуса нет.
		return null;
	}
}

function findFocusNode(key: string): HTMLElement | null {
	for (const node of document.querySelectorAll<HTMLElement>(
		`[${TV_FOCUS_KEY_ATTRIBUTE}]`,
	)) {
		if (node.getAttribute(TV_FOCUS_KEY_ATTRIBUTE) === key) {
			return node;
		}
	}
	return null;
}

// Содержательная цель: карточка/кнопка/скелетон внутри main, но не
// корень страницы и не поиск/сортировка. Для главной без действий
// возвращает null — тогда фокус уходит в навбар.
function findTVContentTarget(root: ParentNode): HTMLElement | null {
	for (const node of root.querySelectorAll<HTMLElement>(
		`[${TV_FOCUS_KEY_ATTRIBUTE}]`,
	)) {
		if (
			!node.hasAttribute(TV_PAGE_ROOT_ATTRIBUTE) &&
			!node.hasAttribute(TV_FOCUS_SECONDARY_ATTRIBUTE)
		) {
			return node;
		}
	}
	return null;
}

// Навбар — резервная цель для страниц без действий (главная): пульт
// сразу оказывается на переключателе разделов, а не на пустом корне.
function findTVNavTarget(): HTMLElement | null {
	return document.querySelector<HTMLElement>(
		`nav [${TV_FOCUS_KEY_ATTRIBUTE}]:not([${TV_FOCUS_SECONDARY_ATTRIBUTE}])`,
	);
}

// Первая содержательная цель: карточка/кнопка, а не корень страницы.
// Если контента ещё нет — корень или сам main, чтобы пульт не висел.
export function findTVFocusTarget(
	root: ParentNode = document,
): HTMLElement | null {
	const nodes = [
		...root.querySelectorAll<HTMLElement>(`[${TV_FOCUS_KEY_ATTRIBUTE}]`),
	];
	const candidates = nodes.filter(
		(node) => !node.hasAttribute(TV_PAGE_ROOT_ATTRIBUTE),
	);
	// Сначала содержательные цели (карточки, кнопки, скелетон), а не
	// поиск/сортировка: они помечены secondary и доступны стрелками.
	const content = candidates.find(
		(node) => !node.hasAttribute(TV_FOCUS_SECONDARY_ATTRIBUTE),
	);
	return (
		content ??
		candidates[0] ??
		nodes[0] ??
		root.querySelector<HTMLElement>("main")
	);
}

// Смена роута в ТВ-режиме: ведём spatial-фокус на первую цель страницы
// и доводим его, когда вместо скелетона появляются карточки. Наблюдатель
// живёт ограниченное время и не мешает, как только пользователь сам
// сдвинул фокус на другой элемент.
export function useTVRouteFocus(tvMode: boolean): void {
	const pathname = useRouterState({
		select: (state) => state.location.pathname,
	});

	// pathname в deps — триггер перезапуска фокуса при смене роута.
	// biome-ignore lint/correctness/useExhaustiveDependencies: pathname в теле не читается.
	useEffect(() => {
		if (!tvMode) {
			return;
		}
		const main = document.querySelector<HTMLElement>("main");
		if (main === null) {
			return;
		}
		let disposed = false;
		let stopped = false;
		let autoKey: string | null = null;
		let debounce: ReturnType<typeof setTimeout> | undefined;
		const stopTimer = setTimeout(() => {
			stopped = true;
			observer.disconnect();
		}, FOCUS_WINDOW_MS);

		const apply = (): void => {
			if (disposed || stopped) {
				return;
			}
			const current = readCurrentFocusKey();
			const currentNode = current === null ? null : findFocusNode(current);
			// Доводим фокус только когда он ещё наш (autoKey: скелетон или
			// корень страницы) либо потерян. Если пользователь уже выбрал
			// цель сам — включая шапку/навбар — не перехватываем: иначе
			// фоновое обновление данных каждый раз сдёргивало бы его
			// из навигации обратно в контент.
			if (
				currentNode !== null &&
				(current !== autoKey || !main.contains(currentNode))
			) {
				return;
			}
			const target =
				findTVContentTarget(main) ??
				findTVNavTarget() ??
				findTVFocusTarget(main);
			if (target === null) {
				return;
			}
			const key = target.getAttribute(TV_FOCUS_KEY_ATTRIBUTE);
			if (key === null || key === "") {
				target.focus({ preventScroll: true });
				return;
			}
			if (key === autoKey && current === key) {
				return;
			}
			autoKey = key;
			void setFocus(key);
		};

		const schedule = (): void => {
			if (debounce !== undefined) {
				clearTimeout(debounce);
			}
			debounce = setTimeout(apply, MUTATION_DEBOUNCE_MS);
		};

		const observer = new MutationObserver(schedule);
		observer.observe(main, {
			childList: true,
			subtree: true,
			attributes: true,
			attributeFilter: [
				TV_FOCUS_KEY_ATTRIBUTE,
				TV_PAGE_ROOT_ATTRIBUTE,
				TV_FOCUS_SECONDARY_ATTRIBUTE,
			],
		});
		schedule();

		return () => {
			disposed = true;
			clearTimeout(stopTimer);
			if (debounce !== undefined) {
				clearTimeout(debounce);
			}
			observer.disconnect();
		};
	}, [pathname, tvMode]);
}
