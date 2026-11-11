import { createFileRoute, redirect } from "@tanstack/react-router";
import type { UploadType } from "../api/upload";
import { shouldBlockTVRoute } from "../features/tv/tvRouteGuard";
import { UploadPage } from "../features/upload/UploadPage";

function parseType(value: unknown): UploadType {
	if (value === "video" || value === "audio" || value === "image") {
		return value;
	}
	return "video";
}

export const Route = createFileRoute("/upload")({
	validateSearch: (search: Record<string, unknown>): { type: UploadType } => ({
		type: parseType(search.type),
	}),
	beforeLoad: ({ location }) => {
		if (shouldBlockTVRoute(location.pathname, location.searchStr)) {
			// TanStack Router управляет редиректами брошенными объектами,
			// а не Error.
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/" });
		}
	},
	component: UploadPage,
});
