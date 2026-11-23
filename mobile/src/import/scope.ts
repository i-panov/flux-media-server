import type { ImportProbe } from "../api/importSeries";

// scope=season media-loader выводит из самой ссылки; для многосезонной
// ссылки он не сможет определить сезон, поэтому просим весь сериал.
export function importScope(probe: ImportProbe): "season" | "series" {
	const singleSeason = (probe.seasons?.length ?? 1) <= 1;
	return singleSeason ? "season" : "series";
}
