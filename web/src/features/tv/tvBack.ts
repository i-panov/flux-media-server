import { useRouter } from "@tanstack/react-router";
import { useEffect } from "react";

// Коды кнопки «Назад» на пультах: 461 — LG webOS, 10009 — Samsung Tizen,
// 8/27 — keyCode для Backspace/Escape в старых WebKit-приставках.
const BACK_KEY_CODES: ReadonlySet<number> = new Set([461, 10009, 8, 27]);
// GoBack/BrowserBack — те же кнопки под другими именами на части платформ.
const BACK_KEYS: ReadonlySet<string> = new Set([
	"Backspace",
	"Escape",
	"GoBack",
	"BrowserBack",
]);

const EDITABLE_SELECTOR = "input, textarea, select";
// Menu.Dropdown рендерит role="menu" (свой static-класс отключён через
// withStaticClass: false, обёртка — Popover.Dropdown), Select — Combobox
// с role="listbox" внутри, обычный Popover — role="dialog".
// Закрытый Modal оставляет в DOM ПУСТОЙ .mantine-Modal-root (без контента
// и role) — его не считаем: иначе Назад молчит на любой странице с
// модалками (детали, коллекции). Открытый виден по .mantine-Modal-content.
const MODAL_SELECTOR =
	// biome-ignore lint/security/noSecrets: CSS-селектор оверлеев, не секрет.
	'[role="dialog"], [role="menu"], [role="listbox"], .mantine-Modal-content, .mantine-Menu-dropdown, .mantine-Popover-dropdown, .mantine-Select-dropdown, .mantine-Combobox-dropdown';

export function isBackKey(
	event: Pick<KeyboardEvent, "key" | "keyCode">,
): boolean {
	return BACK_KEY_CODES.has(event.keyCode) || BACK_KEYS.has(event.key);
}

export function isEditableTarget(target: EventTarget | null): boolean {
	if (!(target instanceof HTMLElement)) {
		return false;
	}
	if (target.isContentEditable) {
		return true;
	}
	return target.closest(EDITABLE_SELECTOR) !== null;
}

export function isModalOpen(): boolean {
	return document.querySelector(MODAL_SELECTOR) !== null;
}

// Возвращает true, если клавиша обработана как «Назад». Не трогаем ввод
// текста и открытые модалки: у Mantine Modal свой Escape и FocusTrap.
export function handleTVBackKey(
	event: KeyboardEvent,
	goBack: () => void,
): boolean {
	if (!isBackKey(event)) {
		return false;
	}
	if (isEditableTarget(event.target)) {
		return false;
	}
	if (isModalOpen()) {
		return false;
	}
	event.preventDefault();
	goBack();
	return true;
}

// Media-клавиши (MediaPlayPause и т.п.) здесь не обрабатываем: spatial-библиотека
// слушает только стрелки и Enter, так что конфликтов нет и перехватывать нечего.
export function useTVBackNavigation(enabled: boolean): void {
	const router = useRouter();

	useEffect(() => {
		if (!enabled) {
			return;
		}
		const onKeyDown = (event: KeyboardEvent) => {
			handleTVBackKey(event, () => {
				router.history.back();
			});
		};
		window.addEventListener("keydown", onKeyDown);
		return () => {
			window.removeEventListener("keydown", onKeyDown);
		};
	}, [enabled, router]);
}
