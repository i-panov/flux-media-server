// Чистое правило перехода сессии, без React: по нему решается, нужно ли
// чистить локальное состояние (очередь, downloads, плеер).
// undefined — сессия ещё грузится; null — достоверно нет входа.

export interface SessionResetDecision {
	readonly hadSession: boolean;
	/** Был вход, а теперь session=null: пора очищать локальные данные. */
	readonly reset: boolean;
}

export function nextSessionResetState(
	hadSession: boolean,
	sessionData: unknown,
): SessionResetDecision {
	if (sessionData === null) {
		return { hadSession: false, reset: hadSession };
	}
	if (sessionData === undefined) {
		return { hadSession, reset: false };
	}
	return { hadSession: true, reset: false };
}
