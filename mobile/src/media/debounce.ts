export const SEARCH_DEBOUNCE_MS = 300;

export interface DebouncedValueScheduler {
	/** Откладывает применение value; следующий вызов отменяет предыдущий. */
	schedule(value: string, apply: (value: string) => void): void;
	/** Отменяет отложенное применение (размонтирование/смена зависимости). */
	cancel(): void;
}

// Чистая таймерная часть debounce: хуку остаётся только React-состояние,
// а поведение «последнее значение после паузы» проверяется fake timers.
export function createDebouncedValue(delayMs: number): DebouncedValueScheduler {
	let timer: ReturnType<typeof setTimeout> | null = null;

	const cancel = () => {
		if (timer !== null) {
			clearTimeout(timer);
			timer = null;
		}
	};

	return {
		schedule(value, apply) {
			cancel();
			timer = setTimeout(() => {
				timer = null;
				apply(value);
			}, delayMs);
		},
		cancel,
	};
}
