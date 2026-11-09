import {
	ACCESS_TOKEN_KEY,
	ApiError,
	type AuthUser,
	fetchMe,
	REFRESH_TOKEN_KEY,
} from "@flux/shared";
import { queryOptions, useQuery } from "@tanstack/react-query";
import { secureStore } from "../storage/secureStore";

export const sessionQueryKey = ["session"] as const;

async function fetchSession(signal: AbortSignal): Promise<AuthUser | null> {
	try {
		return await fetchMe(signal);
	} catch (error) {
		// 401 — нет/протухла сессия; остальное (сеть, 5xx) — ошибка,
		// чтобы UI показал retry, а не отправил на логин.
		if (error instanceof ApiError && error.status === 401) {
			// Refresh не удался: мёртвая пара не должна переживать рестарт.
			try {
				await secureStore.del(ACCESS_TOKEN_KEY);
				await secureStore.del(REFRESH_TOKEN_KEY);
			} catch {
				// Хранилище недоступно — сессия всё равно null в памяти.
			}
			return null;
		}
		throw error;
	}
}

export function sessionQueryOptions() {
	return queryOptions({
		queryKey: sessionQueryKey,
		queryFn: ({ signal }) => fetchSession(signal),
		staleTime: 60_000,
		retry: false,
	});
}

export function useSession() {
	return useQuery(sessionQueryOptions());
}
