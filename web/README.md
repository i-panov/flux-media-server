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
npm run test:e2e:proxy # сквозной тест через реальный прокси
npm run size         # бюджеты бандла
```

## Разработка

Бэкенд запускается отдельно на `http://localhost:8080`. Vite проксирует `/api`
на него; адрес можно переопределить переменной `VITE_API_PROXY`:

```bash
VITE_API_PROXY=http://192.168.1.10:8080 npm run dev
```

В продакшене собранный `dist/` отдаёт Go-сервер с того же origin
(`server.web_dist`, по умолчанию `/app/web` в Docker-образе), поэтому
cookie аутентификации остаются first-party, а CORS не нужен. Веб сознательно
поддерживает только same-origin API: `VITE_API_BASE` и отдельный origin
убраны, потому что `SameSite=Lax`-куки кросс-сайт не отправляются.
В `dev` и `preview` запросы идут через Vite-прокси.

## Offline

Web-клиент работает только в streaming-режиме: offline/downloads сознательно
не переносим из Flutter-легаси. Браузерный offline — отдельный проект
(Cache API/OPFS, квоты, управление кэшем), а не часть текущего веба.
В mobile это следующий этап после авторизации.

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
