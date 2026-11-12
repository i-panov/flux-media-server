import {
	ActionIcon,
	type ActionIconProps,
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
	type RefCallback,
	useCallback,
	useEffect,
	useState,
} from "react";
import {
	TV_FOCUS_KEY_ATTRIBUTE,
	TV_FOCUS_SECONDARY_ATTRIBUTE,
} from "./tvAttributes";
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
	onArrowPress?: (direction: string) => boolean,
	options?: { secondary?: boolean },
): {
	targetRef: RefCallback<T>;
	tvMode: boolean;
	focused: boolean;
} {
	const { tvMode } = useTVMode();
	const secondary = options?.secondary === true;
	// Регистрируем focusable только после появления DOM-узла. Иначе
	// norigin добавляет компонент с node: null, координаты пустые, и
	// после перехода фокус теряется.
	const [nodeReady, setNodeReady] = useState(false);
	const { ref, focused } = useFocusable<object, T>({
		focusKey,
		focusable: tvMode && nodeReady,
		onEnterPress:
			onEnterPress === undefined
				? undefined
				: () => {
						onEnterPress(ref.current);
					},
		onArrowPress:
			onArrowPress === undefined
				? undefined
				: (direction: string) => {
						return onArrowPress(direction);
					},
	});
	// data-tv-focus-key — точка поиска для route-focus: после смены роута
	// хук ждёт появления контента (скелетон → карточки) и ведёт фокус
	// по этим атрибутам, а не по одному таймауту.
	// Callback-ref, а не useEffect: форма/ветка может смонтироваться позже
	// первого рендера (код после отправки письма, данные после скелетона),
	// а effect с неизменными deps на новый DOM-узел уже не сработает.
	const targetRef = useCallback(
		(node: T | null) => {
			// eslint-disable-next-line react-hooks/immutability -- callback-ref синхронизирует внутренний ref useFocusable, чтобы spatial видел поздний DOM-узел.
			(ref as { current: T | null }).current = node;
			if (node === null) {
				setNodeReady(false);
				return;
			}
			setNodeReady(true);
			if (tvMode) {
				node.setAttribute(TV_FOCUS_KEY_ATTRIBUTE, focusKey);
				node.toggleAttribute(TV_FOCUS_SECONDARY_ATTRIBUTE, secondary);
			} else {
				node.removeAttribute(TV_FOCUS_KEY_ATTRIBUTE);
				node.removeAttribute(TV_FOCUS_SECONDARY_ATTRIBUTE);
			}
		},
		[focusKey, tvMode, secondary, ref],
	);
	return { targetRef, tvMode, focused };
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

// Кнопка, доступная с пульта: Enter повторяет клик. В обычном режиме —
// обычная Button с тем же поведением.
export function TVButton({
	focusKey,
	onTVArrowPress,
	...props
}: ButtonProps &
	ComponentPropsWithoutRef<"button"> & {
		focusKey: string;
		// Явный переход стрелкой для составных форм: у полей ввода
		// геометрическая навигация библиотеки ненадёжна.
		onTVArrowPress?: (direction: string) => boolean;
	}) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(
		focusKey,
		clickNode,
		onTVArrowPress,
	);
	return <Button ref={targetRef} {...props} />;
}

// ActionIcon с пультом: избранное, play, retry и прочие компактные действия.
export function TVActionIcon({
	focusKey,
	secondary = false,
	...props
}: ActionIconProps &
	ComponentPropsWithoutRef<"button"> & {
		focusKey: string;
		secondary?: boolean;
	}) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(
		focusKey,
		clickNode,
		undefined,
		{ secondary },
	);
	return <ActionIcon ref={targetRef} {...props} />;
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
