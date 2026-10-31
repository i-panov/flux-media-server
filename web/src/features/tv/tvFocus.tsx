import {
	Button,
	type ButtonProps,
	Tabs,
	type TabsTabProps,
} from "@mantine/core";
import {
	FocusContext,
	getCurrentFocusKey,
	setFocus,
	useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import {
	type ComponentPropsWithoutRef,
	type ReactNode,
	type RefObject,
	useEffect,
} from "react";
import { useTVMode } from "./useTVMode";

// Клик по первой ссылке внутри узла: карточки ведут на детали через
// обычный <a>, поэтому Enter на spatial-фокусе повторяет существующий
// переход без дублирования роутинга.
export function clickFirstLink(node: HTMLElement | null): void {
	(node?.querySelector("a") as HTMLElement | null)?.click();
}

// Клик по самому узлу: кнопки и табы в ТВ-режиме получают DOM-фокус
// через shouldFocusDOMNode, но spatial-библиотека глушит нативный Enter
// (shouldUseNativeEvents: false), так что клик повторяем вручную.
export function clickNode(node: HTMLElement | null): void {
	node?.click();
}

// Хук-мост к spatial-навигации. В обычном режиме компонент
// регистрируется, но не участвует в навигации (focusable: false),
// поэтому поведение вне ТВ-режима не меняется. Возвращает настоящий
// ref объекта — его можно вешать на любой элемент как обычно.
export function useTVFocusable<T extends HTMLElement>(
	focusKey: string,
	onEnterPress?: (node: T | null) => void,
	onArrowPress?: () => boolean,
): {
	targetRef: RefObject<T | null>;
	tvMode: boolean;
	focused: boolean;
} {
	const { tvMode } = useTVMode();
	const { ref, focused } = useFocusable<object, T>({
		focusKey,
		focusable: tvMode,
		onEnterPress:
			onEnterPress === undefined
				? undefined
				: () => {
						onEnterPress(ref.current);
					},
		onArrowPress:
			onArrowPress === undefined
				? undefined
				: () => {
						return onArrowPress();
					},
	});
	return { targetRef: ref, tvMode, focused };
}

// Виртуальная секция: задаёт общий родительский focusKey для карточек
// без лишнего DOM-узла (отступы Stack/Grid не ломаются). ref секции
// вешается на существующий корень страницы, tabIndex — только в ТВ.
export function TVFocusScope({
	focusKey,
	children,
}: {
	focusKey: string;
	children: ReactNode;
}) {
	return (
		<FocusContext.Provider value={focusKey}>{children}</FocusContext.Provider>
	);
}

// Кнопка модалки, доступная с пульта. В обычном режиме — обычная Button.
export function TVModalButton({
	focusKey,
	...props
}: ButtonProps & ComponentPropsWithoutRef<"button"> & { focusKey: string }) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(focusKey, clickNode);
	return <Button ref={targetRef} {...props} />;
}

// Таб плеера: стрелки переключают табы нативно (scoped keydown Mantine),
// spatial-навигацию на них гасим, иначе фокус одновременно уйдёт в сторону.
export function TVTab({
	focusKey,
	...props
}: TabsTabProps & { focusKey: string }) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(
		focusKey,
		clickNode,
		() => false,
	);
	return <Tabs.Tab ref={targetRef} {...props} />;
}

const MODAL_AUTOFOCUS_SELECTOR =
	// biome-ignore lint/security/noSecrets: CSS-селектор автофокуса модалок, не секрет.
	'[role="dialog"] [data-autofocus], .mantine-Modal-content [data-autofocus]';

// Начальный spatial-фокус модалки: первая кнопка футера после монтирования.
// Ветвление детерминированное, без гонки с DOM-фокусом: если внутри модалки
// есть data-autofocus-инпут, spatial-фокус не трогаем — пользователь будет
// печатать, а DOM-фокус уже у Mantine. Иначе доводим spatial-фокус до кнопки.
// Предыдущий spatial-ключ запоминаем при монтировании и возвращаем при
// размонтировании, чтобы пульт продолжил с места открытия модалки.
// Все модалки уже рендерят этот компонент, поэтому возврат централизованный.
export function TVModalAutoFocus({ focusKey }: { focusKey: string }) {
	const { tvMode } = useTVMode();
	useEffect(() => {
		if (!tvMode) {
			return;
		}
		let previousFocusKey: string | null = null;
		try {
			const current = getCurrentFocusKey();
			if (typeof current === "string" && current !== "") {
				previousFocusKey = current;
			}
		} catch {
			// spatial-навигация не инициализирована: возвращать нечего.
		}
		const hasAutofocusField =
			document.querySelector(MODAL_AUTOFOCUS_SELECTOR) !== null;
		const timer = hasAutofocusField
			? undefined
			: setTimeout(() => {
					void setFocus(focusKey);
				}, 60);
		return () => {
			if (timer !== undefined) {
				clearTimeout(timer);
			}
			if (previousFocusKey !== null) {
				void setFocus(previousFocusKey);
			}
		};
	}, [focusKey, tvMode]);
	return null;
}
