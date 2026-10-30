import { useQuery } from "@tanstack/react-query";
import { getHealth, type HealthResponse } from "./client";

export type { HealthResponse };

export interface HealthSnapshot extends HealthResponse {
	latencyMs: number;
}

async function fetchHealth(signal: AbortSignal): Promise<HealthSnapshot> {
	const started = performance.now();
	const health = await getHealth(signal);
	return {
		...health,
		latencyMs: Math.max(0, Math.round(performance.now() - started)),
	};
}

export function useHealthQuery() {
	return useQuery({
		queryKey: ["health"],
		queryFn: ({ signal }) => fetchHealth(signal),
		retry: false,
		refetchOnWindowFocus: false,
	});
}
