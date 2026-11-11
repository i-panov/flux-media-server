import { useEffect, useMemo, useState } from "react";
import { createDebouncedValue, SEARCH_DEBOUNCE_MS } from "./debounce";
import { normalizeSearchQuery } from "./search";

export { SEARCH_DEBOUNCE_MS } from "./debounce";

// Поисковый дебаунс: запрос уходит после паузы ввода, а не на каждую
// букву. Нормализация внутри — чтобы пробельный запрос не создавал
// отдельный query key, а список оставался полным.
export function useDebouncedValue(
	value: string,
	delayMs = SEARCH_DEBOUNCE_MS,
): string {
	const normalized = normalizeSearchQuery(value);
	const [debounced, setDebounced] = useState(normalized);
	const scheduler = useMemo(() => createDebouncedValue(delayMs), [delayMs]);

	useEffect(() => {
		scheduler.schedule(normalized, setDebounced);
		return () => {
			scheduler.cancel();
		};
	}, [normalized, scheduler]);

	return debounced;
}
