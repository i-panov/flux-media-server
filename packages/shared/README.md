# @flux/shared

Общий платформенно-нейтральный код веба и mobile:

- `api/` — `apiFetch`, `ApiError`, refresh-транспорт, health;
- `core/` — zod-схемы и модели медиа, fetch-функции, query-опции, форматтеры;
- `query.ts` — фабрика QueryClient;
- `storage.ts` — интерфейс `KeyValueStore` (реализации в приложениях).

## Границы

Разрешено: `fetch` (через `CoreFetcher`), `zod`, `@tanstack/react-query`,
чистый TypeScript, `AbortSignal`, `URL`/`URLSearchParams`.

Запрещено: DOM (`window`, `document`), `localStorage`/`sessionStorage`,
React/JSX, React Native, роутеры, Mantine. Транспорт и хранилище
подставляет приложение: web — same-origin cookies, mobile — Bearer +
expo-secure-store.

Новый общий код кладите сюда, а не в `web/src/core`.
