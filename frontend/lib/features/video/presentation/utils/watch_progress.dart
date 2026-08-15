/// Порог завершённости: позиция >= 90% длительности считается просмотром
/// до конца. Единое место с порогом (раньше — 2 расходящиеся копии).
const double watchCompletionThreshold = 0.9;

/// True, если просмотр завершён (явный флаг или позиция за порогом).
bool isWatchCompleted({
  required int position,
  required int duration,
  bool completed = false,
}) {
  if (completed) return true;
  return duration > 0 && position >= duration * watchCompletionThreshold;
}

/// Оставляет в «Продолжить просмотр» только незавершённые записи:
/// скрывает completed/досмотренные, но показывает начатые без длительности.
bool shouldShowInContinueWatching({
  required int position,
  required int duration,
  required bool completed,
}) {
  if (isWatchCompleted(
    position: position,
    duration: duration,
    completed: completed,
  )) {
    return false;
  }
  return duration > 0 || position > 0;
}
