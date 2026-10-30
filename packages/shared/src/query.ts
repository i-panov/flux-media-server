import { QueryClient } from "@tanstack/react-query";

// Единые дефолты для веба и mobile (перенесены из web/src/queryClient.ts):
// 30-секундный stale, без авторетраев — повторы только осознанные.
export function createQueryClient(): QueryClient {
	return new QueryClient({
		defaultOptions: {
			queries: {
				staleTime: 30_000,
				retry: 0,
			},
		},
	});
}
