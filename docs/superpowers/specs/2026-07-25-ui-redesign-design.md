# Flux Media Server — UI/UX Redesign Spec

**Date:** 2026-07-25  
**Status:** Approved (pending spec review)

## Overview

Complete redesign of the Flux Media Server client app. The current flat "Media / Libraries / Settings" tab structure is replaced with two clear sections — **Video** and **Audio** — with a unified player, per-user favorites/collections, offline cache, lyrics/translation, and built-in localization (EN/RU). **Mobile-first with adaptive layout** — all screens designed for smartphone first, then adapt to desktop via responsive breakpoints. Single codebase, no separate desktop screens. PWA-compatible (Flutter Web).

## 1. Navigation

- **Two bottom tabs**: "Video" and "Audio"
- **Settings**: gear icon (⚙️) in AppBar, opens as a separate screen (not a tab)
- **Upload**: upload icon (⬆️) in AppBar, opens upload screen (existing functionality, preserved)
- **Localization**: EN/RU, auto-select by system locale, fallback to EN. Language switch in Settings

## 2. Video Section

Horizontal category rows, scrollable vertically:

| Row | Source | Notes |
|-----|--------|-------|
| Continue Watching | WatchProgress where completed=false | Progress bar overlay on card |
| Recently Added | Media WHERE type=video ORDER BY created_at DESC | Horizontal scroll |
| Favorites | User favorites WHERE type=video | Heart icon on card |
| My Collections | User collections (video) | Horizontal scroll of collection covers |
| All Movies | Media WHERE type=video | Full grid below rows |

**Video card**: thumbnail, title, year, heart icon (favorite toggle), download icon (offline cache toggle)

**Video detail screen**: backdrop image, title, year, description, duration, play button, favorite toggle, add to collection, download button

## 3. Audio Section

| Block | Layout | Notes |
|-------|--------|-------|
| Liked Tracks | Vertical list | Track row: cover thumbnail, title, artist, heart, download icon |
| Artists | Horizontal scroll | Circular avatars, tap → artist page |
| Recently Added | Horizontal scroll | Square cards with cover |

**Artist page**: artist name, "Download All" button, track list (liked tracks sorted to top), each track has heart + download icon

**Track row**: 40px cover thumbnail, title, artist name, heart icon, download icon, tap → play

## 4. Player

### 4.1 Unified Playback
- Only one media plays at a time — audio OR video
- Starting video stops audio and vice versa
- Single playback coordinator service manages mutual exclusion

### 4.2 Audio Player

**Mini-player** (above bottom bar):
- Cover thumbnail (36px), track title, artist name, play/pause, skip
- Tap → expands to full-screen player
- Swipe down on full player → minimize to mini-player

**Full-screen audio player**:
- Album cover (large, centered)
- Track title, artist name
- **3 tabs**: Lyrics, Translation, Queue
  - **Lyrics**: synced text, current line highlighted (requires LRC timestamps or timecodes). If no lyrics available — tab hidden.
  - **Translation**: line-by-line translation synced with original. If no translation — tab hidden.
  - **Queue**: upcoming tracks list, reorderable
- Progress bar with seek
- Controls: shuffle, prev, play/pause, next, repeat
- Bottom actions: heart (like), download, add to collection/playlist

### 4.3 Video Player

- Full-screen landscape player (existing behavior preserved)
- Controls overlay: seek bar, play/pause, time
- **Picture-in-Picture**: minimize video to floating window over app
- Tap on PiP window → expand back to fullscreen

## 5. Favorites & Collections (Per-User)

### 5.1 Favorites
- Users can like: tracks, artists, videos
- Each user has their own favorites (shared media library, private favorites)
- Heart icon toggles favorite state
- API: `POST /api/media/:id/favorite`, `DELETE /api/media/:id/favorite`
- API: `GET /api/favorites?type=video|audio|artist`

### 5.2 Collections
- User-created playlists for video (e.g. "Want to Watch", "Horror", etc.)
- Create, rename, delete collections
- Add/remove media items to collections
- API: `POST /api/collections`, `GET /api/collections`, `PUT /api/collections/:id`, `DELETE /api/collections/:id`
- API: `POST /api/collections/:id/items`, `DELETE /api/collections/:id/items/:mediaId`

## 6. Offline Cache

- Download individual track/video (download icon on card/row)
- Download entire artist's tracks ("Download All" button on artist page)
- Download entire collection ("Download All" button on collection)
- Downloaded state: checkmark icon replaces download icon
- **Private storage**: files saved to app-private directory (Flutter `getApplicationSupportDirectory`), NOT accessible to gallery, file managers, or other apps. On Android uses app-specific external storage with `.nomedia`; on iOS uses `Library/Application Support`. On desktop uses app data directory.
- `.nomedia` file placed in cache directory to prevent media scanner indexing on Android
- Downloads persist across app restarts
- Backend streams file via existing `/api/media/:id/stream` endpoint; client caches locally

## 7. Lyrics & Translation

- API: `GET /api/media/:id/lyrics` — returns lyrics text, optional translation, optional sync timestamps (LRC format)
- Lyrics source: extracted from file metadata (ID3 tags for audio) or external metadata service
- Sync: if LRC timestamps available, current line highlighted during playback
- Translation: line-by-line, synced with original. Hidden if not available.
- Both lyrics and translation are optional — tabs appear only when data exists

## 8. Localization

- **Languages**: English (en), Russian (ru)
- **Default**: system locale, fallback to English if unavailable
- **Switch**: language selector in Settings
- **Implementation**: Flutter `intl` + `flutter_localizations` + `gen-l10n`
- **Files**: `lib/l10n/app_en.arb`, `lib/l10n/app_ru.arb`
- All UI strings localized: tab labels, section headers, button labels, settings, error messages, etc.

## 9. Backend API Changes

### New endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | `/api/media/:id/favorite` | Add to favorites | JWT |
| DELETE | `/api/media/:id/favorite` | Remove from favorites | JWT |
| GET | `/api/favorites` | List user favorites (query: type=video\|audio\|artist) | JWT |
| POST | `/api/collections` | Create collection | JWT |
| GET | `/api/collections` | List user collections | JWT |
| PUT | `/api/collections/:id` | Rename collection | JWT |
| DELETE | `/api/collections/:id` | Delete collection | JWT |
| POST | `/api/collections/:id/items` | Add media to collection | JWT |
| DELETE | `/api/collections/:id/items/:mediaId` | Remove media from collection | JWT |
| GET | `/api/media/:id/lyrics` | Get lyrics + translation | JWT |

### New models

- **Favorite** — id, userID, type (video/audio/artist), mediaID (nullable, for video/audio favorites), artistName (nullable, for artist favorites — matched against Media.Artist field), createdAt
- **Collection** — id, userID, name, type (video), createdAt, updatedAt
- **CollectionItem** — id, collectionID, mediaID, addedAt

### Existing endpoints (unchanged)
- All media, library, upload, stream, thumb, progress, metadata endpoints remain as-is

## 10. Frontend Architecture Changes

### New/Modified features

| Feature | Changes |
|---------|---------|
| `core/router/` | Replace 3-tab structure with 2-tab (Video, Audio). Settings as route, not tab. |
| `core/player/` | New: unified playback coordinator service. Manages audio/video mutual exclusion. |
| `features/video/` | New: replaces `features/media/` for video. Category rows, video cards, video detail. |
| `features/audio/` | New: audio section. Liked tracks, artists, artist page, recently added. |
| `features/player/` | Modified: audio mini-player + full-screen player with lyrics/translation/queue tabs. Video player with PiP. |
| `features/favorites/` | New: favorite management (data/domain/presentation). |
| `features/collections/` | New: collection CRUD (data/domain/presentation). |
| `features/offline/` | New: download manager, local cache storage, download state tracking. |
| `features/settings/` | Modified: add language selector, remove server URL tab structure. |
| `l10n/` | New: app_en.arb, app_ru.arb, l10n config. |

### Player coordinator
- Riverpod provider that holds current playback state (type: audio|video, media, position, isPlaying)
- Starting new playback stops current, saves progress, then starts new
- Audio: shows mini-player, full-screen player available
- Video: opens fullscreen, PiP available on minimize

### Offline cache manager
- Riverpod provider tracking download states per media ID
- Downloads to app-private storage (see section 6 for storage details)
- Background download with progress indicator
- `.nomedia` file in cache dir to prevent gallery indexing
- Check downloaded state before network request for playback

## 11. Settings Screen

Grouped card layout (mobile-first), each group in a rounded card:

- **Server**: current server URL displayed (fixes existing bug where URL not shown), "Edit" button to change. Server version shown below.
- **Language**: inline toggle EN / RU (no separate screen)
- **Downloads**: cached media size (e.g. "1.2 GB · 47 files"), "Clear cache" button (red)
- **Account**: current user email displayed, "Logout" button (red)
- **About**: app version

## 12. Adaptive Layout (Responsive)

Single codebase with responsive breakpoints. No separate desktop screens.

### Breakpoint: 600px

| Element | Mobile (< 600px) | Desktop (≥ 600px) |
|---------|-------------------|-------------------|
| Navigation | `BottomNavigationBar` (2 tabs) | `NavigationRail` (side panel) |
| Category rows | Horizontal scroll, 1 item visible | Horizontal scroll, 3-4 items visible |
| Video grid | 2-3 columns (width-based) | 5-6 columns (width-based) |
| Audio track list | Full width rows | Centered max-width 600px |
| Mini-player | Full width above bottom bar | Side panel or floating bar |
| Settings | Full width cards | Centered max-width 500px |
| Artist page | Full width | Centered max-width 600px |

### Implementation
- `LayoutBuilder` + `MediaQuery` at key layout decision points
- Grid column count: `(width / itemWidth).floor().clamp(min, max)` — already partially used in current `MediaListScreen`
- `NavigationRail` vs `BottomNavigationBar` switch based on width
- PWA-compatible: Flutter Web renders the same adaptive widgets
