import { createFileRoute, redirect } from "@tanstack/react-router";
import { sessionQueryOptions } from "../api/session";
import { AdminPage } from "../features/admin/AdminPage";
import { shouldBlockTVRoute } from "../features/tv/tvRouteGuard";

export const Route = createFileRoute("/admin")({
	beforeLoad: async ({ context, location }) => {
		if (shouldBlockTVRoute(location.pathname, location.searchStr)) {
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/" });
		}
		const session = await context.queryClient.ensureQueryData(
			sessionQueryOptions(),
		);
		if (session?.is_admin !== true) {
			// TanStack Router управляет редиректами брошенными объектами,
			// а не Error.
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/" });
		}
	},
	component: AdminPage,
});
