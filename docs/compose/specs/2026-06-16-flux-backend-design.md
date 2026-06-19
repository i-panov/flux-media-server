# Flux Media Server — Backend Design

## [S1] Обзор проекта

**Flux** — личный медиа-сервер (аналог Jellyfin) для просмотра видео (кино, сериалы). Позже планируется добавление аудио (музыка), книг и другого контента.

**Стек бэкенда:**
- Язык: Go 1.26.4
- HTTP фреймворк: Fiber v2
- ORM: GORM
- БД: SQLite
- Транскодирование: FFmpeg (опционально)

**Принципы:**
- Монолит с модулями
- REST API
- Простые логи (INFO, ERROR, DEBUG)
- Unit-тесты для бизнес-логики
- YAML конфигурация

## [S2] Архитектура

```
flux-media-server/
├── backend/
│   ├── cmd/server/main.go          # Точка входа
│   ├── internal/
│   │   ├── config/                 # Конфигурация (YAML)
│   │   ├── models/                 # GORM модели
│   │   ├── handlers/               # HTTP хендлеры (Fiber)
│   │   ├── services/               # Бизнес-логика
│   │   ├── repository/             # Работа с БД (GORM)
│   │   ├── scanner/                # Сканирование папок
│   │   ├── metadata/               # Парсинг имен файлов
│   │   ├── streamer/               # Стриминг видео (FFmpeg)
│   │   ├── email/                  # Отправка кодов по email
│   │   └── middleware/             # JWT middleware
│   ├── configs/
│   │   └── config.example.yaml     # Пример конфигурации
│   ├── go.mod
│   └── go.sum
├── frontend/                       # Flutter (позже)
└── README.md
```

### Модули

| Модуль | Ответственность |
|--------|-----------------|
| **config** | Загрузка и валидация YAML конфигурации |
| **models** | GORM модели (Media, User, WatchProgress, MediaLibrary) |
| **handlers** | HTTP хендлеры, валидация входных данных |
| **services** | Бизнес-логика, оркестрация |
| **repository** | CRUD операции с БД |
| **scanner** | Сканирование папок, обнаружение новых файлов |
| **metadata** | Парсинг имен файлов, получение метаданных |
| **streamer** | Стриминг видео (Direct Play + FFmpeg) |
| **email** | Отправка OTP кодов по SMTP |
| **middleware** | JWT аутентификация |

## [S3] Модели данных

### Media

```go
type Media struct {
    ID           uint      `gorm:"primaryKey"`
    Title        string    `gorm:"index"`
    Year         int
    Description  string
    Type         string    `gorm:"index"` // movie, episode
    Duration     int       // в секундах
    FilePath     string    `gorm:"uniqueIndex"`
    FileSize     int64
    ThumbnailURL string
    MetadataID   *uint
    Metadata     *Metadata
    CreatedAt    time.Time
    UpdatedAt    time.Time
}
```

### Metadata

```go
type Metadata struct {
    ID          uint   `gorm:"primaryKey"`
    ExternalID  string `gorm:"uniqueIndex"` // ID из TMDB/TVDB
    Source      string // tmdb, tvdb
    Title       string
    Year        int
    Description string
    PosterURL   string
    BackdropURL string
    Rating      float64
    Genres      string // JSON array
    Cast        string // JSON array
    CreatedAt   time.Time
}
```

### User

```go
type User struct {
    ID           uint      `gorm:"primaryKey"`
    Email        string    `gorm:"uniqueIndex"`
    DisplayName  string
    AvatarURL    string
    CreatedAt    time.Time
    UpdatedAt    time.Time
}
```

### WatchProgress

```go
type WatchProgress struct {
    ID        uint `gorm:"primaryKey"`
    UserID    uint `gorm:"index"`
    MediaID   uint `gorm:"index"`
    Position  int  // позиция в секундах
    Duration  int  // общая длительность
    Completed bool
    UpdatedAt time.Time
}
```

### MediaLibrary

```go
type MediaLibrary struct {
    ID           uint   `gorm:"primaryKey"`
    Name         string
    Path         string `gorm:"uniqueIndex"`
    Type         string // movie, tv
    Enabled      bool
    ScanInterval int    // в минутах, 0 = отключено
    CreatedAt    time.Time
    UpdatedAt    time.Time
}
```

### Связи

- **Media** → **Metadata** (опциональная связь)
- **WatchProgress** → **User** + **Media** (прогресс пользователя)
- **MediaLibrary** — независимая сущность (папки для сканирования)

## [S4] REST API

### Аутентификация

```
POST   /api/auth/request-code    # Отправить код на email
POST   /api/auth/verify-code     # Проверить код и получить JWT
GET    /api/auth/me              # Текущий пользователь
```

**Логика аутентификации:**
1. Пользователь вводит email
2. Сервер проверяет email в whitelist (из config.yaml)
3. Если email в whitelist → отправляем код на email
4. Если email не в whitelist и `allow_unknown_email: false` → отклоняем
5. Пользователь вводит код → получает JWT токен

### Медиатека

```
GET    /api/media                # Список медиа (фильтры: type, genre, year)
GET    /api/media/:id            # Детали медиа
POST   /api/media                # Создать запись
PUT    /api/media/:id            # Обновить запись
DELETE /api/media/:id            # Удалить запись
GET    /api/media/:id/stream     # Стриминг видео (поддержка Range headers)
GET    /api/media/:id/thumb      # Получить обложку
```

### Библиотеки (папки)

```
GET    /api/libraries            # Список библиотек
POST   /api/libraries            # Добавить библиотеку
PUT    /api/libraries/:id        # Обновить библиотеку
DELETE /api/libraries/:id        # Удалить библиотеку
POST   /api/libraries/:id/scan   # Запустить сканирование
```

### Прогресс

```
GET    /api/progress             # Прогресс всех медиа пользователя
PUT    /api/progress/:mediaId    # Обновить прогресс
DELETE /api/progress/:mediaId    # Сбросить прогресс
```

### Метаданные

```
GET    /api/metadata/search      # Поиск метаданных (парсинг имен)
POST   /api/metadata/:mediaId/refresh # Обновить метаданные для медиа
```

## [S5] Конфигурация (config.yaml)

```yaml
server:
  host: "0.0.0.0"
  port: 8080
  debug: false

database:
  path: "./data/flux.db"

auth:
  jwt_secret: "change-me-in-production"
  code_length: 6
  code_expiry: 300  # 5 минут
  allowed_emails:
    - user1@example.com
    - user2@example.com
  allow_unknown_email: false
  smtp:
    host: "smtp.gmail.com"
    port: 587
    username: "your-email@gmail.com"
    password: "your-app-password"
    from: "Flux <noreply@example.com>"

scanner:
  enabled: true
  interval: 30  # минуты

media:
  thumbnail_path: "./data/thumbnails"
  allowed_extensions:
    - .mp4
    - .mkv
    - .avi
    - .mov
    - .wmv
```

## [S6] Стриминг видео

### Direct Play

- Передача файла целиком с поддержкой HTTP Range headers
- Клиент может перематывать видео
- Кодировка:原始 формат файла

### Транскодирование (опционально)

- Используется FFmpeg для конвертации видео
- Применяется когда клиент не поддерживает формат файла
- Конвертация в H.264/AAC для максимальной совместимости

### API стриминга

```
GET /api/media/:id/stream
  Headers:
    Range: bytes=0-1024  # опционально, для перемотки
  Response:
    200 OK (весь файл)
    206 Partial Content (часть файла)
    Content-Type: video/mp4
    Content-Range: bytes 0-1024/12345678
```

## [S7] Сканирование папок

### Процесс сканирования

1. Получаем список включенных библиотек из БД
2. Для каждой библиотеки рекурсивно обходим папки
3. Находим файлы с разрешенными расширениями
4. Проверяем есть ли файл уже в БД (по FilePath)
5. Если новый → создаем запись Media
6. Парсим имя файла для получения базовых метаданных
7. Создаем превью (thumbnail) из видео

### Парсинг имен файлов

**Форматы:**
- `Movie.Name.2024.mkv` → Title: "Movie Name", Year: 2024
- `Movie Name (2024).mkv` → Title: "Movie Name", Year: 2024
- `Series.S01E05.Episode.Name.mkv` → Series: "Series", Season: 1, Episode: 5

**Примеры:**
```
The.Matrix.1999.mkv → The Matrix, 1999
Inception (2010).mp4 → Inception, 2010
Breaking.Bad.S01E01.Pilot.mkv → Breaking Bad, S01E01
```

## [S8] Аутентификация (детали)

### JWT токен

```json
{
  "user_id": 1,
  "email": "user@example.com",
  "exp": 1234567890
}
```

### Хранение OTP кодов

Коды хранятся в memory (map) с TTL. При перезапуске сервера коды сбрасываются.

### Middleware

```go
func AuthMiddleware(c *fiber.Ctx) error {
    token := c.Get("Authorization")
    // валидация JWT
    // добавление user_id в context
}
```

## [S9] Будущие функции (ROADMAP)

### Фаза 2: Внешние API для метаданных

- **TMDB** — фильмы и сериалы (https://www.themoviedb.org/documentation/api)
- **TVDB** — сериалы (https://thetvdb.github.io/v4-api/)
- **MusicBrainz** — музыка (https://musicbrainz.org/doc/MusicBrainz_API)

### Фаза 3: Аудио (музыка)

- Поддержка аудио форматов (MP3, FLAC, AAC, OGG)
- Потоковое воспроизведение музыки
- Плейлисты
- Метаданные из тегов (ID3, Vorbis)
- Интеграция с MusicBrainz для обложек альбомов

### Фаза 4: Книги

- Поддержка форматов (EPUB, PDF, CBZ, CBR)
- Встроенный ридер
- Закладки и прогресс чтения
- Метаданные из Open Library API

### Фаза 5: Дополнительные возможности

- Транскодирование видео в реальном времени
- Субтитры (внешние и встроенные)
- Мульти-аудио дорожки
- DLNA/UPnP сервер
- API для сторонних клиентов

## [S10] Требования к окружению

- Go 1.26.4+
- SQLite3 (CGO required)
- FFmpeg (для транскодирования)
- SMTP сервер (для отправки кодов)

## [S11] Запуск и развертывание

```bash
# Сборка
cd backend
go build -o flux-server ./cmd/server

# Запуск
./flux-server -config configs/config.yaml

# Разработка
go run ./cmd/server -config configs/config.yaml
```
