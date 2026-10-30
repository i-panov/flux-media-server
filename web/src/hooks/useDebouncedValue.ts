import { useEffect, useState } from "react";

const DEFAULT_DEBOUNCE_MS = 300;

// Поисковый дебаунс: запрос уходит после паузы ввода, пробелы
// по краям не ищутся. Один для списков и модалок выбора.
export function useDebouncedValue(
	value: string,
	delayMs = DEFAULT_DEBOUNCE_MS,
): string {
	const [debounced, setDebounced] = useState(value);
	useEffect(() => {
		const timer = setTimeout(() => {
			setDebounced(value.trim());
		}, delayMs);
		return () => {
			clearTimeout(timer);
		};
	}, [value, delayMs]);
	return debounced;
}
