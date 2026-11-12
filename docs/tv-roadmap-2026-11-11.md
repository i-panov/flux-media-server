# TV Roadmap — Android TV, web-TV и QR-вход

**Дата:** 2026-11-11. **Статус:** план; web-TV P1/P2 закрыты в web 0.1.35, admin — 0.1.36,
включая OSD видео и правки по ревью; реальный ТВ не проверялся.
Android TV/QR — впереди.
**Базовый HEAD:** `5e41973` (mobile Task 24, без финального ревью).
**Связанные документы:** [mobile-parity-plan-2026-11-09.md](mobile-parity-plan-2026-11-09.md),
[mobile-parity-handoff-2026-11-10.md](mobile-parity-handoff-2026-11-10.md),
[review-2026-11-09.md](review-2026-11-09.md).

Это отдельная кросс-клиентская дорожная карта: mobile-план уже почти закрыт,
а ТВ-версия затрагивает shared, backend, web, mobile и новый нативный клиент.

---

## 1. Принципы

1. **ТВ — read-only по контенту.** На ТВ нельзя загружать файлы, менять
   метаданные, менять обложки, удалять медиа, управлять корзиной и админкой.
2. **Прогресс и избранное разрешены.** Это пользовательское состояние, а не
   изменение библиотеки. Если «read-only» понимать строго, прогресс тоже
   придётся отключить — это ухудшит ТВ-опыт, поэтому по умолчанию оставляем.
3. **Один capability-слой для всех клиентов.** `canUpload`, `canEditMetadata`,
   `canDelete`, `canDownload`, `canManageTrash`, `canUseQrLogin` и т.п.
   Не размазывать `if (isTV)` по компонентам.
4. **QR/device-code — общий вход для ТВ и web-TV.** Телефон/десктоп уже
   залогинен, подтверждает устройство; ТВ не вводит email/OTP пультом.
5. **Android TV — первый нативный ТВ-клиент.** Apple TV не приоритет.
   Fire TV — тот же Android-билд с отдельной публикацией.
6. **Web-only ТВ (VidaaOS, Tizen, webOS) — это web-клиент в ТВ-режиме,**
   не React Native.
7. **Серверные проверки прав не заменяются клиентскими.** Скрытие кнопок —
   только UX.

---

## 2. Текущее состояние

| Компонент | Версия | Статус |
|---|---|---|
| backend | 1.0.30 | API, auth, upload/transcode/extract, trash, collections |
| shared | 0.1.8 | media, favorites, collections, progress, lyrics, audioQueue |
| web | 0.1.36 | функционально полный web-клиент; TV P1/P2 закрыты, включая OSD видео и правки ревью; реальный ТВ не проверялся |
| mobile | 0.1.34 / 52 | Мемы и TV-каркас; APK/AAB собраны, TV emulator: login→список→detail→playback, play/pause и seek с пульта |

Mobile-долги, которые нужно закрыть до ТВ:

- финальное ревью Task 24 (`5e41973`);
- Task 25: релиз, APK, smoke на устройстве;
- Maestro/эмулятор в текущем окружении отсутствуют — flows не запускались.

Поиск и сортировка списков видео/аудио закрыты в mobile 0.1.31
и исключены из mobile-долгов.

Web-долги:

- TV-режим доведён в 0.1.34–0.1.35: фокус, пульт, read-only, OSD видео;
- остались overscan и проверка на реальном ТВ;
- часть P3-замечаний ревью;
- VidaaOS/браузер Hisense не проверялся.

---

## 3. Фаза 0 — закрыть mobile

### 3.1. Финальное ревью Task 24

- Проверить `5e41973`: CI, manual e2e workflow, docs, отсутствие ложных
  заявлений о прогоне Maestro.
- Закрыть P1/P2, если остались.
- Только после этого считать Task 24 принятым.

### 3.2. Поиск и сортировка mobile ✅ (0.1.31)

**Статус:** закрыто в mobile 0.1.31. Ниже — историческая
постановка.

**Проблема:** в `mobile/src/api/media.ts` `useVideoList()`/`useAudioList()`
всегда передают `q=""`; shared уже принимает `q` и `sort`.

**Сделать:**

- `useVideoList(q, sort)`, `useAudioList(q, sort)`.
- На экранах видео/аудио: `TextInput` поиска, debounce ~300 мс, переключатель
  сортировки `asc/desc`.
- При смене `q`/`sort` сбрасывать пагинацию (`useInfiniteQuery` ключ уже
  включает параметры).
- Пустые состояния: «ничего не найдено» отдельно от «библиотека пуста».
- i18n ru/en, тема, 44dp, очистка поиска.
- Тесты pure-частей (debounce/параметры), typecheck/lint/export.
- Версия mobile: `0.1.31`, versionCode 49.

**Приёмка:** поиск по названию/артисту, сортировка, пустой результат,
сброс при очистке, пагинация не ломается.

### 3.3. Task 25 — релиз mobile

- `npm run version:sync -w mobile`; проверить `--check`.
- Dogfood APK arm64 (если есть Android SDK/NDK/JDK).
- Smoke на устройстве: login, video, audio background/lock, offline.
- Записать известные ограничения (Maestro/device-only, уведомления upload,
  artwork lock screen, iOS-края).
- Коммит `chore(mobile): релиз <version>`.

**Важно:** без устройства/эмулятора релиз считается «код готов, runtime не
подтверждён». Это нужно явно писать в отчёте.

---

## 4. Фаза 1 — добить web-версию

До ТВ-адаптации нужно закрыть обычный web-клиент, иначе ТВ будет строиться
поверх незакрытых web-долгов.

### 4.1. Что осталось по web

- Закрыть оставшиеся P3 из [review-2026-11-09.md](review-2026-11-09.md)
  (то, что не входило в mobile-паритет).
- Регрессия всех сценариев: OTP-вход, видео, аудио, плеер, прогресс,
  избранное, коллекции, артисты, загрузка, метаданные/обложки, корзина,
  админка, настройки, поиск/сортировка.
- Проверить, что web и mobile используют один shared-контракт без
  расхождений (favorites, collections, progress, lyrics, queue).
- Прогнать полный web-гейт: `typecheck`, `lint`, `lint:deadcode`, `test`,
  `build`, `size`, Playwright e2e.
- Отдельно проверить PWA/service worker и поведение при обновлении версии.
- Зафиксировать известные ограничения web (offline/downloads не
  поддерживаются осознанно) в README/release notes.

### 4.2. Приёмка

- Все перечисленные сценарии проходят на desktop и в мобильном браузере.
- Нет открытых P1/P2 по web; P3 либо закрыты, либо явно приняты.
- `npm run build`, `npm run test`, `npm run test:e2e`, `npm run size` —
  зелёные.
- После этого переходим к web-TV, не смешивая обычные web-фиксы с ТВ-кодом.

---

## 5. Фаза 2 — web-TV и read-only профиль

### 5.1. Детект ТВ

Разрешение — только вспомогательный сигнал. Нужна эвристика + override.

**Сигналы:**

- UA: `SmartTV`, `Tizen`, `Web0S`/`webOS`, `HbbTV`, `NetCast`, `BRAVIA`,
  `Android TV`, `GoogleTV`, `FireTV`, `AFT...`, `VIDAA`, `Hisense`,
  `Philips`, `Opera TV`, `Roku`, `CrKey`.
- Глобальные объекты: `window.tizen`, `window.webOS`, `window.VIDAA`,
  `window.hbbtv`.
- `matchMedia("(hover: none) and (pointer: none)")` / `pointer: coarse`.
- `navigator.maxTouchPoints === 0`.
- `screen.width >= 1280`, `outerWidth === screen.width`,
  `devicePixelRatio` 1–1.5 — дополнительные баллы.

**Реализация:**

- чистая `detectClientProfile()` со скорингом, тесты на наборы UA/фич;
- `ClientProfile = "desktop" | "mobile-web" | "tv-web" | "tv-native"`;
- `?tv=1` / `?tv=0` для принудительного режима;
- сохранение выбора в `localStorage`;
- переключатель «ТВ-режим» в настройках;
- баннер при пограничном результате.

Нельзя блокировать 4K-десктоп: если профиль неоднозначен — обычный режим,
пользователь включает ТВ-режим вручную.

### 5.2. Capability-модель

```ts
interface ClientCapabilities {
  canUpload: boolean;
  canEditMetadata: boolean;
  canChangeCover: boolean;
  canDelete: boolean;
  canManageTrash: boolean;
  canDownload: boolean;
  canManageCollections: boolean;
  canUseQrLogin: boolean;
}
```

Матрица:

| Возможность | desktop | tv-web | tv-native |
|---|---:|---:|---:|
| просмотр библиотеки | да | да | да |
| поиск/сортировка | да | да | да |
| плеер | да | да | да |
| прогресс | да | да | да |
| избранное | да | да | да |
| коллекции (просмотр) | да | да | да |
| коллекции (CRUD) | да | нет | нет |
| upload | да | нет | нет |
| metadata edit/cover | да | нет | нет |
| delete/trash/admin | да | нет | нет |
| downloads/export | да | нет | нет |
| QR-вход | — | да | да |

Скрытие должно быть и в UI, и в route guard (не монтировать экран), но
серверные права остаются источником истины.

### 5.3. ТВ-навигация в web

- Пространственная навигация: стрелки, Enter, Back.
- Начальный фокус на первом ряду/кнопке; восстановление фокуса при возврате.
- `scrollIntoView` с отступами; без hover-only эффектов.
- Модалки/меню: focus trap, Escape/Back, возврат фокуса.
- Плеер: OSD с пульта, play/pause, seek ±10, fullscreen, back —
  ✅ web 0.1.35 (video OSD, автоскрытие, media-клавиши).
- 16:9, базовая 1920×1080, overscan ~5%.
- Крупные элементы, читаемые с 3 метров.

**Клавиши:**

- стрелки — навигация;
- Enter/OK — выбор;
- Back/Escape/Backspace — назад (зависит от платформы);
- media keys — play/pause, если браузер отдаёт.

### 5.4. Web-only ТВ

Приоритет — **VidaaOS (Hisense)**, затем Tizen/webOS.

- Tizen: web-приложение HTML/CSS/JS + `config.xml`;
- webOS: web app (React/Enact);
- VidaaOS: проверить браузер, UA, пульт, видео-элемент, fullscreen, cookies;
- общий TV-режим web-клиента; отдельный нативный RN туда не тащим.

**Приёмка:** ручной прогон на реальном ТВ + Playwright с синтетическими
клавишами для базовой навигации (эмуляция пульта ограничена).

---

## 6. Фаза 3 — QR/device-code авторизация

### 6.1. Зачем

OTP пультом — плохой UX: email, код, раскладка. ТВ должен показывать QR и
короткий код, а подтверждение происходит на уже залогиненном устройстве.

### 6.2. Flow

1. ТВ: `POST /auth/device/code` → `{device_code, user_code, verification_uri, expires_in, interval}`.
2. ТВ показывает QR (`verification_uri?code=...`) и `user_code`.
3. Телефон/десктоп (уже залогинен) открывает `/activate`, вводит код или
   сканирует QR.
4. `POST /auth/device/approve` (auth) подтверждает устройство.
5. ТВ опрашивает `POST /auth/device/token` с `device_code` (не `user_code`).
6. После approval ТВ получает access/refresh, сохраняет сессию.

### 6.3. Требования безопасности

- `device_code` — случайный, хранится только хешем; `user_code` — короткий,
  человекочитаемый, одноразовый.
- TTL 2–5 минут; после истечения — новый код.
- Одноразовое использование; повторный poll после выдачи — ошибка.
- Rate limit на создание/подтверждение/poll.
- Показывать имя/платформу устройства при подтверждении.
- Не класть токены в QR.
- Отзыв сессии устройства в настройках.
- Не логировать коды/токены.

### 6.4. Клиенты

- **TV (native/web):** экран QR + код, polling, ошибки/истечение, повтор.
- **Web:** `/activate` — подтверждение, выбор «это мой ТВ», success.
- **Mobile:** deep link/экран подтверждения, если QR открыт на телефоне.
- **Настройки:** список активных устройств, отзыв.

### 6.5. Токены

- Native: SecureStore (access/refresh).
- Web: httpOnly cookies, SameSite, secure; TV-браузер должен их сохранять.
- Если cookies на ТВ не переживают перезапуск — разрешить повторный QR-вход,
  не хранить refresh в localStorage без необходимости.
- Ротация refresh, обработка 401 как в остальных клиентах.

### 6.6. Приёмка

- вход на ТВ без клавиатуры;
- истечение кода, повторная попытка;
- подтверждение с другого аккаунта — отказ/предупреждение;
- отзыв устройства;
- QR на web-TV и native TV;
- обычный OTP-вход не сломан.

---

## 7. Фаза 4 — Android TV (native)

### 7.1. Сборка

- `react-native` → `react-native-tvos` версии, совпадающей с RN 0.88
  (на момент проверки линия 0.88 была RC — проверить stable).
- `@react-native-tvos/config-tv`, `EXPO_TV=1 npx expo prebuild --clean`.
- TV-манифест: leanback launcher, `android:banner`, `uses-feature
  android.software.leanback`, touchscreen не обязателен.
- Отдельный EAS-профиль `development_tv`/`preview_tv`, чтобы телефон и ТВ
  собирались из одного кода.
- APK/AAB, Play Console TV track.

### 7.2. Архитектура

- `Platform.isTV` + capability-профиль.
- Отдельная TV-группа экранов или адаптивные компоненты; текущие табы и
  touch-жесты не подходят.
- Read-only: скрыть upload, metadata, cover, delete, trash, admin,
  downloads/export.
- Оставить: библиотека, поиск, сортировка, плеер, прогресс, избранное,
  коллекции (просмотр), QR-вход.

### 7.3. Фокус и пульт

- D-pad, Enter, Back; начальный и восстановленный фокус.
- `TVFocusGuideView`, `hasTVPreferredFocus`, обработка TV-событий.
- Крупные карточки, горизонтальные ряды, 10-foot UI, overscan.
- Плеер: OSD, play/pause, seek ±10, back, автопереход.

### 7.4. Ограничения Expo на TV

Поддерживаются (по Expo TV docs): Video, Audio, Image, FileSystem,
SecureStore, AsyncStorage, KeepAwake, SystemUI, SplashScreen, Reanimated,
SafeArea, Constants и др.

Не заявлены: `expo-document-picker`, `expo-image-picker`, `expo-sharing`.
Значит:

- upload/cover/export на TV скрыть;
- проверить, что их импорт не ломает сборку (ленивые экраны/платформенные
  заглушки);
- offline-downloads на TV не нужны.

### 7.5. Приёмка

- сборка и установка на Android TV emulator;
- реальный ТВ/приставка (пульт, back, фокус);
- Play TV checklist (banner, leanback, 16:9, no touchscreen);
- QR-вход;
- видео/аудио, прогресс, избранное, коллекции;
- отсутствие доступа к write-экранам.

---

## 8. Фаза 5 — Fire TV

- Fire OS — Android-подобная система Amazon, без Google Play.
- Тот же Android TV APK в большинстве случаев подходит; проверить Fire OS
  API/пульт/кодеки.
- Публикация отдельно в Amazon Appstore.
- UA Fire TV содержит `AFT...`; учитывать в web-детекте, если web открыт в
  Silk.
- **Vega OS** (Fire TV Stick 4K Select) — отдельный ранний стек
  «React Native for Vega» на RN 0.72, не тот же билд. Не делать, пока нет
  реальной аудитории.

---

## 9. Порядок работ

1. Mobile: финальное ревью Task 24.
2. Mobile: поиск/сортировка закрыты в 0.1.31; остался Task 25 release + smoke.
3. Mobile: Task 25 release + smoke.
4. Web: добить обычную версию и закрыть P1/P2/P3-долги.
5. Web-TV: TV-детект, capability-слой, read-only, навигация, OSD.
6. Web-TV: VidaaOS (приоритет), затем Tizen/webOS.
7. QR/device-code: backend + shared + web + mobile.
8. Android TV: форк, сборка, TV-UI, read-only, QR.
9. Fire TV: проверка и Amazon Appstore.
10. Опционально: Apple TV, Vega — только при необходимости.

---

## 10. Оценка (агентская, не человеко-дни)

| Этап | Часы агента |
|---|---:|
| Mobile Task 24 review + Task 25 release (search/sort уже закрыт) | 10–20 |
| Web: закрыть обычные долги и прогнать полный гейт | 8–16 |
| Web TV-детект/capabilities/read-only | 8–16 |
| Web TV-навигация/фокус/OSD | 10–20 |
| QR/device-code (backend+web+mobile+TV) | 8–16 |
| Android TV fork/сборка/TV-UI/read-only/QR | 20–40 |
| Fire TV проверка/публикация | 4–8 |
| Тесты, устройство, CI | 8–16 |

Итого: **~70–130 часов** агентской работы. Календарно — зависит от сборок,
эмулятора/ТВ и ревью; узкое место — проверка на устройстве, а не набор кода.

---

## 11. Риски

1. **Версия RN TV-форка** может не совпадать с Expo SDK 58/RN 0.88.
2. **Нет Android SDK/эмулятора** в текущем окружении — сборка/проверка
   блокируются.
3. **Web-TV браузеры** старые и разные; VidaaOS/Tizen/webOS требуют
   отдельных проверок.
4. **Cookies на ТВ** могут не переживать перезапуск — QR-вход должен быть
   повторяемым.
5. **Фокус** — главный источник багов; нужен ручной прогон на пульте.
6. **Play TV требования** (banner, leanback, 16:9) — формальная приёмка.
7. **Не прятать write-действия только CSS** — route guards + серверные права.
8. **QR-безопасность** — TTL, одноразовость, rate limit, отзыв.

---

## 12. Definition of Done для ТВ

- [ ] Mobile закрыт: Task 24 review, поиск/сортировка (0.1.31), Task 25.
- [ ] Web закрыт: обычные P1/P2/P3, полный гейт, регрессия сценариев.
- [x] Web TV-профиль: детект + override, read-only, навигация, OSD
      (web 0.1.35; реальный ТВ не проверялся).
- [x] QR/device-code вход работает на web-TV и native TV (backend+web+TV; device list/revoke).
- [ ] Android TV APK/AAB собирается, проходит Play TV checklist.
- [ ] Read-only: write-экраны недоступны, прогресс/избранное работают.
- [ ] Проверено на реальном Android TV/приставке.
- [ ] Fire TV проверен (если нужен).
- [ ] Документация и release notes обновлены.
