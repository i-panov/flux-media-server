import { ACCESS_TOKEN_KEY, logout, REFRESH_TOKEN_KEY } from "@flux/shared";
import type { QueryClient } from "@tanstack/react-query";
import { secureStore } from "../storage/secureStore";
import { markSessionSignedOut } from "./session";

// Локальный выход: серверный logout best-effort и не блокирует очистку
// (иначе зависшая сеть оставила бы токены и данные на устройстве).
// session=null выставляется первым, чтобы подписчики увидели переход и
// очистили очередь/downloads; остальные queries удаляются следом.
export async function signOutLocal(queryClient: QueryClient): Promise<void> {
	// Передаём refresh текущего устройства: сервер удалит только его
	// сессии, а не все устройства пользователя.
	const refreshToken = await secureStore.get(REFRESH_TOKEN_KEY);
	void logout(refreshToken ?? undefined).catch(() => undefined);
	// Висящие запросы (включая /auth/me) не должны вернуть user уже после
	// session=null. Заодно отменяем возможный refresh до удаления токенов.
	await queryClient.cancelQueries();
	markSessionSignedOut(queryClient);
	// Оба ключа удаляем независимо: ошибка одного не должна оставить второй.
	await Promise.allSettled([
		secureStore.del(ACCESS_TOKEN_KEY),
		secureStore.del(REFRESH_TOKEN_KEY),
	]);
}
