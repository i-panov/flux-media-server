# Flux Web

Веб-клиент медиа-сервера Flux: React 19, TypeScript, Vite, Mantine, TanStack Router/Query.

## Требования

- Node.js 22+

## Команды

```bash
cd web
npm install
npm run dev          # http://localhost:5173
npm run build        # генерация маршрутов, typecheck и сборка
npm run preview      # просмотр собранной версии
npm run lint         # Biome + ESLint
npm run lint:deadcode # Knip
npm run test         # Vitest
npm run test:e2e     # Playwright
npm run size         # бюджеты бандла
```

## Разработка

Бэкенд запускается отдельно на `http://localhost:8080`. Vite проксирует `/api`
на него; адрес можно переопределить переменной `VITE_API_PROXY`:

```bash
VITE_API_PROXY=http://192.168.1.10:8080 npm run dev
```

В продакшене собранный `dist/` будет отдавать Go-сервер с того же origin,
поэтому cookie аутентификации останутся first-party, а CORS не понадобится.
Раздача пока не реализована — до неё фронт ходит к отдельному бэкенду
через proxy (и в `dev`, и в `preview`).

## Структура

- `src/api/` — клиент API и query-хуки.
- `src/components/` — общие компоненты оболочки.
- `src/features/` — экраны по фичам.
- `src/routes/` — файловые маршруты TanStack Router (`routeTree.gen.ts` генерируется).
- `src/sw.ts` — service worker для PWA.

## Правила

- Общение и комментарии — по-русски.
- Перед правками — skill `code-style`.
- `core` не импортирует DOM, роутер или Mantine: этот код потом переедет в общий пакет для React Native.
