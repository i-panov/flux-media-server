// Поколение сессии: увеличивается при выходе, смене сервера и успешном
// входе. Асинхронные операции (refresh, /auth/me), начатые в старом
// поколении, не должны менять токены и состояние новой сессии.
let generation = 0;

export function currentSessionGeneration(): number {
	return generation;
}

export function bumpSessionGeneration(): number {
	generation += 1;
	return generation;
}
