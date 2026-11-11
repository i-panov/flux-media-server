// Чистые хелперы поиска/сортировки списков: без React и RN, чтобы
// debounce-хук и API-опции использовали одну нормализацию запроса.
export type SortOrder = "asc" | "desc";

// Пробелы по краям не ищутся, а серии внутренних пробелов схлопываются:
// случайный двойной пробел не должен создавать отдельный кэш-ключ запроса.
export function normalizeSearchQuery(value: string): string {
	return value.trim().replace(/\s+/g, " ");
}

// Один переключатель на оба таба: desc («новые») — дефолт, asc — «старые».
export function nextSort(sort: SortOrder): SortOrder {
	return sort === "asc" ? "desc" : "asc";
}
