// Чистая политика транспорта: её проверяют тесты, а провайдер и хуки
// только применяют решение. Так внешняя пауза (lock screen/шторка/потеря
// фокуса) не зависит от stale-намерения в ref.

export interface TogglePlaybackState {
	/** Фактическое состояние нативного плеера, а не намерение. */
	playing: boolean;
	/** Идёт загрузка/замена источника. */
	loading: boolean;
	/** Плеер буферизует уже запрошенное воспроизведение. */
	buffering: boolean;
	/** Последнее локальное намерение играть. */
	desiredPlaying: boolean;
}

// Пауза по тапу: играет — ставим паузу; грузится или буферизует начатое —
// отменяем намерение. Если играть никто не просил, это не пауза, а play:
// после внешней паузы desired может быть ещё true, но playing уже false.
export function shouldPauseOnToggle(state: TogglePlaybackState): boolean {
	return (
		state.playing || state.loading || (state.desiredPlaying && state.buffering)
	);
}

export interface TrackChangePlaybackState {
	playing: boolean;
	loading: boolean;
	buffering: boolean;
	desiredPlaying: boolean;
}

// Продолжать ли звук после ручного next/prev. Буферизация уже начатого
// воспроизведения — это тоже «играло»: иначе следующий трек встал бы на
// паузу, хотя пользователь просто переключил буферизующийся трек.
// После внешней паузы desired сбрасывается sync-эффектом, поэтому stale
// намерение само по себе не включает звук.
export function wasPlayingBeforeChange(
	state: TrackChangePlaybackState,
): boolean {
	return (
		state.playing ||
		(state.desiredPlaying && (state.loading || state.buffering))
	);
}

// Нужно ли продолжать звук после смены трека. Конец трека — всегда да
// (repeat one перезапускает тот же, иначе играет следующий), даже если
// status уже успел прислать playing=false.
export function shouldResumeAfterTrackChange(
	wasPlaying: boolean,
	didJustFinish: boolean,
): boolean {
	return didJustFinish || wasPlaying;
}

export interface StatusIntentState {
	playing: boolean;
	loading: boolean;
	buffering: boolean;
	/** iOS: playing/paused/waitingToPlayAtSpecifiedRate; Android: playing/paused. */
	timeControlStatus: string;
	desiredPlaying: boolean;
}

// Каким должно стать намерение после очередного status. Во время загрузки
// не вмешиваемся (локальное действие главнее). playing=true — точно играем.
// «paused» — реальная пауза, включая внешнюю паузу во время буферизации:
// её нужно погасить, иначе один тап play станет no-op. «waiting»/буферизация
// начатого play намерение сохраняют.
export function desiredAfterStatus(state: StatusIntentState): boolean {
	if (state.loading) {
		return state.desiredPlaying;
	}
	if (state.playing) {
		return true;
	}
	if (state.timeControlStatus === "paused") {
		return false;
	}
	// Android во время буферизации отдаёт timeControlStatus "playing" и
	// playing=true; iOS — "waitingToPlayAtSpecifiedRate" и playing=false.
	// В обоих случаях намерение сохраняем.
	return state.desiredPlaying;
}
