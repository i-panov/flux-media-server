# Device-code / QR авторизация — 2026-11-12

Новый способ входа для ТВ и устройств без удобной клавиатуры. OTP-вход
по email сохранён и не менялся.

## Flow

1. ТВ/приставка: `POST /api/auth/device/code` с `{device_name, platform}`.
   В ответ приходят `device_code`, `user_code`, `verification_uri`,
   `verification_uri_complete`, `expires_in`, `interval`.
2. ТВ показывает QR (`verification_uri_complete`) и короткий `user_code`.
3. Пользователь на уже авторизованном телефоне/десктопе открывает
   `/activate?code=...` (или вводит код) и подтверждает устройство.
4. ТВ опрашивает `POST /api/auth/device/token` с `device_code`.
   `pending` → ждать, `ok` → access/refresh, `expired` → новый код.
5. Устройство появляется в «Активных устройствах»; сессию можно отозвать.

## Endpoint'ы

| Метод | Путь | Доступ |
|---|---|---|
| POST | `/api/auth/device/code` | публично, auth rate limit |
| POST | `/api/auth/device/token` | публично, отдельный лимит 120/мин |
| POST | `/api/auth/device/inspect` | access token |
| POST | `/api/auth/device/approve` | access token |
| GET | `/api/auth/devices` | access token |
| DELETE | `/api/auth/devices/:id` | access token |

## Безопасность

- В БД хранятся только SHA-256 `device_code` и `user_code`; сырые коды
  возвращаются один раз.
- TTL — `auth.code_expiry` (минимум 120 секунд), код одноразовый:
  `approved → consumed` атомарно, повторный poll получает `expired`.
- `device_code` — 32 случайных байта; `user_code` — 8 символов из
  алфавита без похожих `0/O/1/I`.
- Токены не попадают в QR; QR содержит только URL активации и код.
- Подтверждение требует авторизованную сессию; чужой код без сессии
  не подтвердить.
- Poll имеет отдельный лимит 120/мин на IP: 3-секундный интервал не
  упирается в общий auth-лимит.
- Refresh-токены ротируются; метаданные устройства (имя, платформа)
  переезжают в новую запись, `last_used_at` обновляется.
- В JWT добавлен `jti`: два входа одного пользователя в одну секунду
  больше не дают одинаковый refresh JWT.
- Имя устройства по умолчанию — браузер и ОС (User-Agent), для native —
  модель/платформа. `device_id` стабилен на установку/браузер, поэтому
  повторные входы группируются в одно устройство.
- Имена уникальны в рамках пользователя (регистронезависимо); при
  совпадении сервер добавляет `(2)`, `(3)`.
- Logout удаляет только сессии текущего устройства; полный logout —
  только если клиент не прислал refresh/куку.

## Конфиг

`server.public_url` — внешний адрес веб-клиента для QR. Если пуст,
используется scheme+Host запроса (удобно для LAN/dev). В production
задайте, например:

```yaml
server:
  public_url: "https://flux.example.com"
```

## Клиенты

- **Web:** `/login` → «Войти по QR-коду»; `/activate` — подтверждение
  с показом имени/платформы; `/settings` — список устройств и отзыв.
- **Android TV:** при `Platform.isTV` логин сразу открывает QR + код;
  OTP остаётся кнопкой «Войти по email». Проверено на эмуляторе:
  QR отрисован, код подтверждён с web, сессия создана; после
  подтверждения TV сразу переходит в библиотеку.
- **Mobile:** `/activate` — подтверждение по deep link/коду; в настройках
  «Активные устройства» и отзыв; на TV deep link подтверждения скрыт
  (read-only профиль).

## Проверка

- backend: `TestDeviceCodeLoginFlow` — создание, pending, inspect,
  approve, выдача токенов, повторный poll, список, отзыв и отказ refresh.
- web: ручной прогон на локальном backend — QR, `/activate`, approve,
  список устройств и revoke.
- shared: `qrMatrix` детерминирован и зависит от содержимого.
