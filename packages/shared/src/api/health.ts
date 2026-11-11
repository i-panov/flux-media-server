import { useQuery } from "@tanstack/react-query";
import { getHealth, type HealthResponse } from "./client";

export interface HealthSnapshot extends HealthResponse {
	latencyMs: number;
}

async function fetchHealth(signal: AbortSignal): Promise<HealthSnapshot> {
	const started = Date.now();
	const health = await getHealth(signal);
	return {
		...health,
		latencyMs: Math.max(0, Math.round(Date.now() - started)),
	};
}

export function useHealthQuery(enabled = true) {
	return useQuery({
		queryKey: ["health"],
		queryFn: ({ signal }) => fetchHealth(signal),
		retry: false,
		refetchOnWindowFocus: false,
		enabled,
	});
}
