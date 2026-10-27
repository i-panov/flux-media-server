import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { queryClient } from "../queryClient";
import {
	type AuthUser,
	fetchMe,
	logout,
	requestCode,
	verifyCode,
} from "./auth";
import { ApiError } from "./client";

const sessionQueryKey = ["session"];

async function fetchSession(signal: AbortSignal): Promise<AuthUser | null> {
	try {
		return await fetchMe(signal);
	} catch (error) {
		// Только 401 означает «нет сессии». Остальное (500, сеть, 429) —
		// транзиентные проблемы: их пробрасываем в error-состояние, иначе
		// guard закэширует null и будет вечно слать на логин.
		if (error instanceof ApiError && error.status === 401) {
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
		refetchOnWindowFocus: false,
	});
}

export function useSession() {
	return useQuery(sessionQueryOptions());
}

// Сброс локальной сессии без запроса: серверной сессии уже нет
// (401 после неудачного refresh) — держать UI «вошедшим» нельзя.
export function clearSessionData() {
	queryClient.setQueryData(sessionQueryKey, null);
}

export function useRequestCodeMutation() {
	return useMutation({
		mutationFn: (email: string) => requestCode(email),
	});
}

export function useVerifyCodeMutation() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ email, code }: { email: string; code: string }) =>
			verifyCode(email, code),
		onSuccess: (data) => {
			// Ответ уже содержит пользователя — класть в кэш напрямую,
			// а не инвалидировать: иначе навигация следом застанет
			// в guard ещё свежий null и отскочит обратно на логин.
			queryClient.setQueryData(sessionQueryKey, data.user);
		},
	});
}

export function useLogoutMutation() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: () => logout(),
		onSuccess: () => {
			queryClient.setQueryData(sessionQueryKey, null);
		},
	});
}
