import {
	cancelExtractJob,
	fetchExtractedAudio,
	fetchExtractStatus,
	startExtract,
} from "@flux/shared";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";
import type { Media } from "../core/media";
import { ApiError } from "./client";

const POLL_INTERVAL_MS = 1500;
// Сколько подряд неудачных опросов терпим: сеть может моргнуть.
const MAX_POLL_FAILURES = 3;

export function useExtractedAudio(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["media", mediaId, "extracted"],
		queryFn: () => fetchExtractedAudio(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

// POST → либо готовый трек (200), либо задание (202 {job_id}).
// Опрос — циклом из start(), остановка — флагом отмены: уход со
// страницы прекращает опрос, задание на сервере продолжает жить.
export function useExtractAudio(mediaId: number) {
	const queryClient = useQueryClient();
	const [jobId, setJobId] = useState<number | null>(null);
	const [error, setError] = useState<string | null>(null);
	const cancelled = useRef(false);
	// Два быстрых start() видят один и тот же стейт: стейт-гарда
	// недостаточно, повторный вызов упирается в синхронный флаг.
	const startingRef = useRef(false);

	useEffect(
		() => () => {
			cancelled.current = true;
		},
		[],
	);

	const finish = useCallback(
		(track: Media | null) => {
			setJobId(null);
			if (track !== null) {
				queryClient.setQueryData(["media", mediaId, "extracted"], track);
				// Списки и деталь — обновить, а связку и сабы не трогать:
				// трек только что записан вручную, рефетч вернул бы 404/гонку,
				// а сабы извлечение не меняет.
				void queryClient.invalidateQueries({
					queryKey: ["media"],
					predicate: (query) =>
						query.queryKey[2] !== "extracted" && query.queryKey[2] !== "subs",
				});
			}
		},
		[mediaId, queryClient],
	);

	const start = useCallback(async (): Promise<Media | null> => {
		if (jobId !== null || startingRef.current) {
			return null;
		}
		startingRef.current = true;
		try {
			setError(null);
			cancelled.current = false;
			let id: number;
			try {
				const started = await startExtract(mediaId);
				if (started.kind === "track") {
					finish(started.track);
					return started.track;
				}
				id = started.jobId;
				setJobId(id);
			} catch (startError) {
				setError(
					startError instanceof ApiError && startError.message !== ""
						? startError.message
						: "Extraction failed",
				);
				return null;
			}
			let failures = 0;
			while (!cancelled.current) {
				await sleep(POLL_INTERVAL_MS);
				if (cancelled.current) {
					return null;
				}
				try {
					const status = await fetchExtractStatus(id);
					failures = 0;
					if (status.status === "done") {
						const track = status.media ?? null;
						finish(track);
						return track;
					}
					if (status.status === "error") {
						setError(status.error ?? "Extraction failed");
						setJobId(null);
						return null;
					}
				} catch (pollError) {
					failures += 1;
					if (failures >= MAX_POLL_FAILURES) {
						setError(
							pollError instanceof ApiError && pollError.message !== ""
								? pollError.message
								: "Polling failed",
						);
						setJobId(null);
						return null;
					}
				}
			}
			return null;
		} finally {
			startingRef.current = false;
		}
	}, [finish, jobId, mediaId]);

	const cancel = useCallback(async () => {
		if (jobId === null) {
			return;
		}
		cancelled.current = true;
		try {
			await cancelExtractJob(jobId);
		} catch {
			// 404/409: задание уже исчезло или готово — итог тот же.
		}
		setJobId(null);
		void queryClient.invalidateQueries({
			queryKey: ["media", mediaId, "extracted"],
		});
	}, [jobId, mediaId, queryClient]);

	return { jobId, isExtracting: jobId !== null, error, start, cancel };
}
