import { ACCESS_TOKEN_KEY, logout, REFRESH_TOKEN_KEY } from "@flux/shared";
import type { QueryClient } from "@tanstack/react-query";
import { secureStore } from "../storage/secureStore";
import { sessionQueryKey } from "./session";

// Локальный выход: серверный logout best-effort, затем гарантированно
// чистим токены и кэш. session=null, чтобы login не делал лишний /auth/me.
export async function signOutLocal(queryClient: QueryClient): Promise<void> {
	try {
		await logout();
	} catch {
		// Сессия могла уже истечь/сеть недоступна — локальную всё равно чистим.
	}
	try {
		await secureStore.del(ACCESS_TOKEN_KEY);
		await secureStore.del(REFRESH_TOKEN_KEY);
	} catch {
		// Хранилище недоступно — сессия всё равно сбрасывается в памяти.
	}
	queryClient.removeQueries();
	queryClient.setQueryData(sessionQueryKey, null);
}
