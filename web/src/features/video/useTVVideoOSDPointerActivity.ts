import { type RefObject, useEffect, useRef } from "react";

// Мышью OSD тоже живёт: сдвиг/клик показывает контролы и сбрасывает
// таймер. Подавляем только клик, который сам был первым pointerdown
// на скрытой панели. Если панель уже показана pointermove, клик должен
// работать сразу.
export function useTVVideoOSDPointerActivity(
	show: () => void,
	visible: boolean,
	videoRef: RefObject<HTMLVideoElement | null>,
): void {
	const visibleRef = useRef(visible);
	useEffect(() => {
		visibleRef.current = visible;
	}, [visible]);
	const suppressGesture = useRef(false);

	useEffect(() => {
		const reveal = () => {
			if (visibleRef.current) {
				return;
			}
			// Синхронно: pointerdown после pointermove уже должен видеть
			// панель показанной, без ожидания React-эффекта.
			visibleRef.current = true;
			show();
		};
		const insideShell = (target: EventTarget | null): boolean => {
			const shell = videoRef.current?.parentElement ?? null;
			return target instanceof Node && shell !== null && shell.contains(target);
		};
		const onPointerDown = (event: PointerEvent) => {
			const wasHidden = !visibleRef.current;
			reveal();
			if (wasHidden && insideShell(event.target)) {
				suppressGesture.current = true;
				event.preventDefault();
				event.stopPropagation();
			}
		};
		const onMouseDown = (event: MouseEvent) => {
			if (suppressGesture.current) {
				event.preventDefault();
				event.stopPropagation();
			}
		};
		const onClick = (event: MouseEvent) => {
			if (suppressGesture.current && event.detail > 0) {
				suppressGesture.current = false;
				event.preventDefault();
				event.stopPropagation();
			}
		};
		const onPointerUp = () => {
			// Клик после подавленного pointerdown идёт синхронно до таймера;
			// если click не пришёл (drag), снимаем флаг.
			setTimeout(() => {
				suppressGesture.current = false;
			}, 0);
		};
		window.addEventListener("pointermove", reveal, { passive: true });
		window.addEventListener("pointerdown", onPointerDown, true);
		window.addEventListener("mousedown", onMouseDown, true);
		window.addEventListener("click", onClick, true);
		window.addEventListener("pointerup", onPointerUp, true);
		return () => {
			window.removeEventListener("pointermove", reveal);
			window.removeEventListener("pointerdown", onPointerDown, true);
			window.removeEventListener("mousedown", onMouseDown, true);
			window.removeEventListener("click", onClick, true);
			window.removeEventListener("pointerup", onPointerUp, true);
		};
	}, [show, videoRef]);
}
