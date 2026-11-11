import { createFileRoute, redirect } from "@tanstack/react-router";
import { TrashPage } from "../features/trash/TrashPage";
import { shouldBlockTVRoute } from "../features/tv/tvRouteGuard";

export const Route = createFileRoute("/trash")({
	beforeLoad: ({ location }) => {
		if (shouldBlockTVRoute(location.pathname, location.searchStr)) {
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/" });
		}
	},
	component: TrashPage,
});
