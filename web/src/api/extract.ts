import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";
import { z } from "zod";
import { type Media, mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";

const POLL_INTERVAL_MS = 1500;
// Сколько подряд неудачных опросов терпим: сеть может моргнуть.
const MAX_POLL_FAILURES = 3;

const jobSchema = z.object({
	job_id: z.number(),
});

const jobStatusSchema = z.object({
	id: z.number(),
	status: z.string(),
	error: z.string().nullish(),
	media: mediaSchema.nullish(),
});

async function fetchExtractedAudio(mediaId: number): Promise<Media | null> {
	try {
		const body = await apiFetch<unknown>(`/media/${mediaId}/extracted`);
		return mediaSchema.parse(body);
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return null;
		}
		throw error;
	}
}

export function useExtractedAudio(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["media", mediaId, "extracted"],
		queryFn: () => fetchExtractedAudio(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

async function cancelExtractJob(jobId: number): Promise<void> {
	await apiFetch<unknown>(`/media/extract/${jobId}`, { method: "DELETE" });
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
				// Списки и деталь — обновить, а связку не трогать: трек
				// только что записан вручную, рефетч вернул бы 404/гонку.
				void queryClient.invalidateQueries({
					queryKey: ["media"],
					predicate: (query) => query.queryKey[2] !== "extracted",
				});
			}
		},
		[mediaId, queryClient],
	);

	const start = useCallback(async (): Promise<Media | null> => {
		if (jobId !== null) {
			return null;
		}
		setError(null);
		cancelled.current = false;
		let id: number;
		try {
			const body = await apiFetch<unknown>(`/media/${mediaId}/extract`, {
				method: "POST",
			});
			if (typeof body !== "object" || body === null || !("job_id" in body)) {
				const track = mediaSchema.parse(body);
				finish(track);
				return track;
			}
			id = jobSchema.parse(body).job_id;
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
				const raw = await apiFetch<unknown>(`/media/extract/${id}`);
				const status = jobStatusSchema.parse(raw);
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
