import shutil, sqlite3, sys
from pathlib import Path

db = sqlite3.connect(sys.argv[1])
# Настоящий файл для проверки обрезки: без media-loader и без гонок за кэш.
library = Path(sys.argv[1]).parent / "video"
library.mkdir(parents=True, exist_ok=True)
clip_source = library / "clip-source.mp4"
shutil.copyfile(Path(__file__).parent.parent / "fixtures" / "video.mp4", clip_source)
db.execute("PRAGMA foreign_keys=ON")
now = "2026-01-01 00:00:00"
media = [
    (9001, "Пилот", "/tmp/pilot.mp4", 1200, "episode"),
    (9002, "Реальный фильм", "/tmp/film.mp4", 5400, "movie"),
    (9003, "Отдельный фильм", "/tmp/standalone.mp4", 4800, "movie"),
    (9004, "E2E эпизод", "/tmp/e2e-episode.mp4", 1500, "movie"),
    (9006, "E2E видео из UI", "/tmp/e2e-ui.mp4", 1200, "movie"),
    (9007, "E2E обрезка", str(clip_source), 1, "movie"),
]
for media_id, title, path, duration, kind in media:
    db.execute("""INSERT INTO media (id, title, type, video_kind, file_path, duration, created_at, updated_at)
                  VALUES (?, ?, 'video', ?, ?, ?, ?, ?)""", (media_id, title, kind, path, duration, now, now))
db.execute("""INSERT INTO works (id, kind, title, description, cover_url, year, created_at, updated_at)
              VALUES (9001, 'series', 'Реальный сериал', '', '', 2026, ?, ?)""", (now, now))
db.execute("""INSERT INTO seasons (id, work_id, season_number, title, position, created_at, updated_at)
              VALUES (9001, 9001, 1, 'Сезон 1', 0, ?, ?)""", (now, now))
db.execute("""INSERT INTO work_items (id, season_id, media_id, position, episode_number, created_at)
              VALUES (9001, 9001, 9001, 0, 1, ?)""", (now,))
db.execute("""INSERT INTO works (id, kind, title, description, cover_url, year, created_at, updated_at)
              VALUES (9002, 'film_series', 'Реальная серия фильмов', '', '', 2025, ?, ?)""", (now, now))
db.execute("""INSERT INTO work_items (id, work_id, media_id, position, created_at)
              VALUES (9002, 9002, 9002, 0, ?)""", (now,))
db.execute("""INSERT INTO users (id, email, is_admin, created_at, updated_at)
              VALUES (9001, 'catalog-admin@example.com', 1, ?, ?)""", (now, now))
db.execute("""INSERT INTO users (id, email, is_admin, created_at, updated_at)
              VALUES (9002, 'e2e@example.com', 1, ?, ?)""", (now, now))
db.execute("""INSERT INTO users (id, email, is_admin, created_at, updated_at)
              VALUES (9003, 'clip@example.com', 1, ?, ?)""", (now, now))
db.execute("""INSERT INTO franchises (id, name, description, cover_url, created_at, updated_at)
              VALUES (9001, 'Реальная франшиза', '', '', ?, ?)""", (now, now))
db.execute("INSERT INTO franchise_entries (id, franchise_id, work_id, position) VALUES (9001, 9001, 9001, 0)")
db.execute("INSERT INTO franchise_entries (id, franchise_id, work_id, position) VALUES (9002, 9001, 9002, 1)")
db.execute("INSERT INTO franchise_entries (id, franchise_id, media_id, position) VALUES (9003, 9001, 9003, 2)")
db.commit()
