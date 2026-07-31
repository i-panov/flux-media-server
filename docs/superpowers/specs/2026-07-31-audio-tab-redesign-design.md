# Audio Tab Redesign — Design Spec

**Date:** 2026-07-31  
**Status:** Draft

## Problem

The Audio tab currently mimics a video/media library: tracks are shown as cards, tapping a track opens a full detail page (`MediaDetailRoute`) with a "Play" button. This is wrong for audio. Streaming services like Apple Music and Spotify show flat track lists where a tap immediately starts playback in a mini-player. Lyrics/translation are accessed from the player, not from a detail page.

## Goals

1. **Tap on track = immediate playback** via mini-player (no detail page as primary path).
2. **Flat track lists** instead of cards — compact rows with visible action buttons.
3. **Context-aware queue** — the section the user tapped in becomes the play queue.
4. **Detail page remains accessible** via long-press, not as the primary path.
5. **Auto-advance** to next track when current track completes.

## Non-Goals

- Redesign of video tab.
- Changes to backend API.
- Changes to lyrics/translation data layer.
- New features beyond what already exists (lyrics, queue, favorites, download, collections).

---

## Component Changes

### 1. `AudioTrackRow` — Redesigned track row

**Current:** `Card` + `ListTile` with cover, title, artist, favorite/download buttons. Tap → `MediaDetailRoute`.

**New:**

- **No `Card`** — flat row with thin `Divider` between rows (or no divider, rely on spacing).
- **Cover:** square 48×48, rounded corners (8px radius), `AuthNetworkImage`.
- **Text:** title (bodyMedium) + artist (bodySmall) in two lines.
- **Trailing:** `IconButton` favorite → `IconButton` download → `PopupMenuButton` (⋯ menu).
- **⋯ menu items:** Play, Add to queue, Add to collection, Edit metadata, Details.
- **Currently playing track:** row background tinted with `primaryContainer`; cover replaced with animated equalizer icon or play icon in `primary` color.
- **Tap on row** → `onPlay` callback (starts playback).
- **Long-press on row** → `onDetails` callback (opens `MediaDetailRoute`).
- **Props:** `media`, `isPlaying` (bool), `isFavorite`, `onPlay`, `onFavorite`, `isDownloaded`, `onDownload`, `onDetails`, `onAddToQueue`, `onAddToCollection`, `onEditMetadata`.

### 2. `AudioScreen` — Main audio page restructure

**Current sections:** Liked Tracks (horizontal `AudioTrackRow` list), Artists (horizontal cards), Recently Added (horizontal `MediaCard` 160px).

**New sections:**

```
┌─ AppBar ──────────────────────────────┐
│  [Аудио]              [upload] [⚙]     │
├───────────────────────────────────────┤
│  🔍 SearchBar (filters All Tracks)     │
├───────────────────────────────────────┤
│  ❤️ Liked Tracks (flat list, max 10)   │
│  track 1 ... ♥ ⬇ ⋮                     │
│  track 2 ... ♥ ⬇ ⋮                     │
├───────────────────────────────────────┤
│  👥 Artists (horizontal carousel)      │
│  [Artist A] [Artist B] [Artist C] →    │
├───────────────────────────────────────┤
│  🎵 All Tracks (flat list, paginated)  │
│  track A ... ♡ ⬇ ⋮                     │
│  track B ... ♡ ⬇ ⋮                     │
│  ... (loadMore on scroll)              │
└───────────────────────────────────────┘
│  Mini-player (if playing)              │
└───────────────────────────────────────┘
```

**Changes:**
- **Recently Added section removed.** Replaced by "All Tracks" — a flat, paginated list of all audio tracks.
- **Liked Tracks** — flat list of `AudioTrackRow` (max 10). Tap → play with queue = liked tracks.
- **Artists** — unchanged horizontal carousel of `ArtistCard`. Tap → `ArtistPage`.
- **All Tracks** — flat list of `AudioTrackRow` with `loadMore` pagination. Tap → play with queue = all tracks.
- **SearchBar** — filters the All Tracks list (uses `searchQueryProvider` properly: submit triggers search, empty clears).
- **Tap on track in any section** → `PlayQueueNotifier.setQueue(sectionTracks, startIndex: index)`.
- **Long-press on track** → `MediaDetailRoute`.

### 3. `ArtistPage` — Updated for new interaction model

**Changes:**
- Uses new flat `AudioTrackRow` (no `Card`).
- **Tap on track** → `PlayQueueNotifier.setQueue(artistTracks, startIndex: index)`.
- **Long-press on track** → `MediaDetailRoute`.
- Structure unchanged: two sections (Liked Tracks, All Tracks) + "Download All" button in AppBar.

### 4. `AudioMiniPlayer` — No structural changes

Already works correctly: cover, title/artist, play/pause, close, progress bar. Tap opens `AudioPlayerScreen`.

### 5. `AudioPlayerScreen` — Show current track from coordinator

**Current issue:** `AudioPlayerScreen` receives `Media media` as a route parameter. If the queue advances (next/previous), the screen still shows the original `widget.media` for lyrics/translation tabs.

**Fix:** Lyrics and Translation tabs should read the **current media from `playbackCoordinatorProvider`**, not from `widget.media`. The `widget.media` parameter is only used for initial navigation/auto-play check.

**No other changes** — tabs (Lyrics, Translation, Queue), controls (seek, prev/next, play/pause, volume) remain as-is.

### 6. Auto-advance on track completion

**Current:** `PlaybackCoordinator._onCompleted` saves progress and sets `PlaybackCompleted`. No auto-next.

**Fix:** When `completedStream` fires:
1. Save progress (already done).
2. Check `playQueueProvider` for `hasNext`.
3. If `hasNext` → call `playQueueProvider.notifier.next()` (which calls `_coordinator.play(nextItem)`).
4. If no next track → set state to `PlaybackCompleted` (current behavior).

**Implementation note:** `PlaybackCoordinator` has access to `Ref`, so it can read `playQueueProvider`. However, there's a circular dependency risk: `PlayQueueNotifier` watches `playbackCoordinatorProvider.notifier`. To avoid this, `PlaybackCoordinator` should read `playQueueProvider` lazily via `_ref.read()` only in `_onCompleted`, not in constructor.

---

## Data Flow

```
User taps track in AudioScreen
  → AudioScreen reads section tracks from mediaListProvider
  → calls PlayQueueNotifier.setQueue(sectionTracks, startIndex: tappedIndex)
    → PlayQueueNotifier sets state, calls PlaybackCoordinator.play(items[startIndex])
      → PlaybackCoordinator opens audio stream, starts playback
      → state = PlaybackPlaying(media, 'audio', isPaused: false)
      → AudioMiniPlayer appears (watches playbackCoordinatorProvider)
  → User can:
    - Tap mini-player → AudioPlayerScreen (lyrics, translation, queue)
    - Tap next/prev in mini-player or full player → PlayQueueNotifier.next()/previous()
    - Track completes → PlaybackCoordinator._onCompleted → auto-next via playQueueProvider
```

---

## Files to Modify

| File | Change |
|------|--------|
| `frontend/lib/features/audio/presentation/widgets/audio_track_row.dart` | Full rewrite: flat row, new props, playing state, ⋯ menu |
| `frontend/lib/features/audio/presentation/screens/audio_screen.dart` | Remove Recently Added, add All Tracks flat list, wire play queue, fix search |
| `frontend/lib/features/audio/presentation/screens/artist_page.dart` | Wire play queue on tap, use new AudioTrackRow |
| `frontend/lib/features/player/presentation/screens/audio_player_screen.dart` | Lyrics/Translation tabs read current media from coordinator |
| `frontend/lib/features/player/data/providers/playback_coordinator.dart` | Auto-advance on completion via playQueueProvider |

## Files NOT Modified

- `AudioMiniPlayer` — already correct.
- `PlayQueueNotifier` / `play_queue_provider.dart` — already correct (`setQueue`, `next`, `previous` all work).
- `LyricsProvider` — no changes needed.
- Backend — no changes.
- Router (`app_router.dart`) — no new routes needed. `AudioPlayerRoute` already takes `Media`.

---

## Edge Cases

1. **Empty queue after track ends** — state becomes `PlaybackCompleted`, mini-player hides. User can tap another track.
2. **User navigates away from AudioScreen during playback** — mini-player is global (in main scaffold), playback continues.
3. **Search active** — All Tracks list is filtered. Tap on filtered track → queue = filtered list (not full list). This is intentional — user sees what they searched.
4. **Video starts during audio playback** — `PlaybackCoordinator.play()` already handles mutual exclusion (stops audio, starts video). Mini-player hides because `type != 'audio'`.
5. **AudioPlayerScreen open when track auto-advances** — lyrics/translation tabs update because they read from coordinator, not `widget.media`.
