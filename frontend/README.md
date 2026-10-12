# frontend

Flux media server — Flutter client.

## Notes

- Debug and release builds keep separate local data (server URL, login,
  offline cache): switching build flavors "loses" the server/login —
  this is intentional, re-enter them in the new flavor.
- Server URL contract: exactly one trailing `/api`
  (e.g. `http://host:8080/api`).
- Self-signed certificates require the explicit opt-in toggle.
  Notification artwork picks the toggle up only after app restart
  (the background audio handler snapshots it at startup).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
