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

// Пультовые коды 461/10009/GoBack/BrowserBack не превращаются браузером
// в Escape, поэтому Mantine их не видит. Синтезируем Escape на активном
// элементе (у Select обработчик висит на input) — верхний слой закроется
// своим штатным путём и вернёт фокус, история не трогается.
function synthesizeEscape(overlay: Element): void {
	const active = document.activeElement;
	const target = active instanceof HTMLElement ? active : overlay;
	const escapeEvent = new KeyboardEvent("keydown", {
		key: "Escape",
		code: "Escape",
		bubbles: true,
		cancelable: true,
	});
	Object.defineProperty(escapeEvent, "keyCode", { get: () => 27 });
	Object.defineProperty(escapeEvent, "which", { get: () => 27 });
	target.dispatchEvent(escapeEvent);
}

function isRemoteOnlyBackKey(
	event: Pick<KeyboardEvent, "key" | "keyCode">,
): boolean {
	return (
		event.key !== "Backspace" &&
		event.key !== "Escape" &&
		event.keyCode !== 8 &&
		event.keyCode !== 27
	);
}

// Возвращает true, если клавиша обработана как «Назад». Не трогаем ввод
// текста. Открытый overlay (модалка/меню/select) закрываем синтетическим
// Escape: для настоящего Escape его обработает сам Mantine, для кодов
// пульта без этого Назад уходил бы в историю под открытым слоем.
// Исключение — пультовый Назад при фокусе в поле Select: это не набор
// текста, а команда закрыть верхний слой; Backspace по-прежнему правит текст.
export function handleTVBackKey(
	event: KeyboardEvent,
	goBack: () => void,
): boolean {
	if (!isBackKey(event)) {
		return false;
	}
	const overlay = document.querySelector(MODAL_SELECTOR);
	if (isEditableTarget(event.target)) {
		if (overlay !== null && isRemoteOnlyBackKey(event)) {
			event.preventDefault();
			synthesizeEscape(overlay);
			return true;
		}
		return false;
	}
	if (overlay !== null) {
		if (event.key === "Escape" && event.keyCode === 27) {
			return false;
		}
		event.preventDefault();
		synthesizeEscape(overlay);
		return true;
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
