# Mobile 0.1.30 — release notes (2026-11-11)

**Версии:** mobile `0.1.30` / versionCode `48`, shared `0.1.8`,
backend `1.0.29`, web `0.1.31`.
**Ветка:** `master`. **Статус:** функции Tasks 1–24 готовы; DoD паритета
**не закрыт** (нет поиска/сортировки списков). Публикация dogfood APK и
device-smoke — Task 25.

## Что реализовано

- **Вход и сервер:** OTP-вход, access/refresh-токены только в SecureStore,
  публичная настройка URL (`/server`) до входа, сброс сессии и logout с
  очисткой кэша, очереди, скачиваний и persisted state.
- **Видео:** список с пагинацией, детали, плеер (play/pause, seek ±10,
  скорость 0.5–2, fullscreen, PiP, wakelock), resume по прогрессу,
  избранное, коллекции, source link, extract audio и удаление (admin).
- **Аудио:** список, очередь (start/enqueue/next/prev/shuffle/repeat/
  reorder), persisted queue, полный и мини-плеер, seek/скорость, прогресс и
  resume, фон и lock screen, lyrics/translation с sync-подсветкой, артисты
  и их треки.
- **Библиотека:** continue watching, избранное (медиа и артисты), коллекции
  с вложенностью и bulk-операциями, корзина (restore, purge, empty для
  admin).
- **Загрузка:** document picker (video/audio/image), очередь на 2
  параллельных загрузки, progress, отмена/retry, обработка duplicate,
  polling фоновой обработки.
- **Метаданные:** редактирование полей и артистов, смена обложки,
  удаление в корзину.
- **Offline:** resumable download с Bearer, индекс и лимит кеша, offline
  playback из `file://`, экспорт/«Сохранить в Files», удаление из кеша.
- **Настройки:** тема system/light/dark, язык ru/en, health сервера,
  logout.
- **Тесты и CI:** Vitest на чистую логику и контракты, 18 Maestro-flow в
  `.maestro/` (созданы в Tasks 4–23), проверки `expo install --check` и
  `expo config --type introspect` в CI, ручной Android e2e workflow с
  Metro, `adb reverse`, логами и скриншотами в артефактах.

## Известные ограничения

- **Нет поиска и сортировки списков:** shared API `q`/`sort` готов, но в
  табах видео/аудио нет UI; это единственный известный функциональный
  пробел паритета, DoD открыт.
- **Maestro не запускался:** в окружении разработки нет maestro, adb,
  эмулятора и KVM. Flow проверены только парсингом YAML; отчёт не
  утверждает, что сценарии прошли.
- **Device-smoke не выполнен:** background audio, lock screen, PiP и
  offline проверены кодом и unit-тестами, но не на железе. Expo Go для
  этих функций не подходит — нужен dev/release build.
- **`mobile-e2e.yml` не проверен:** ручной workflow
  (`workflow_dispatch`), в push/PR не входит; возможны правки образа,
  AVD и таймаутов. Медиа-зависимые flow в нём намеренно не запускаются;
  debug-APK требует Metro на хосте и `adb reverse`.
- **Нет system notifications для upload:** прогресс и «готово» видны только
  на открытом экране загрузок; уведомлений в шторке нет.
- **Нет artwork на lock screen:** обложка требует Bearer-заголовков,
  которые система не отправит; в metadata есть title/artist/album.
- **iOS-края не проверены:** Keychain переживает `clearState`,
  PiP/background audio, security-scoped URL для upload и audio session
  требуют отдельного прогона на устройстве.
- **Offline-коллекции неполные:** скачиваются медиа, серверное дерево
  коллекций в offline доступно только для уже скачанных элементов.

## Проверки

```bash
npm run typecheck -w mobile
npm run lint -w mobile
npm run test -w mobile
npm run version:sync -w mobile -- --check
(cd mobile && EXPO_OFFLINE=1 npx expo install --check)
(cd mobile && npx expo config --type introspect)
(cd mobile && npx expo export --platform android --output-dir dist)
```

YAML всех `.maestro/*.yaml` и `.github/workflows/*.yml` был проверен
парсером локально (Python/PyYAML) в рамках Task 24; отдельного CI-шага
для YAML нет. Новые зависимости не добавлялись.
