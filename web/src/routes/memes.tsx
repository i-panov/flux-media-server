import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import {
	shouldBlockTVRoute,
	tvRouteRedirectTarget,
} from "../features/tv/tvRouteGuard";

export const Route = createFileRoute("/memes")({
	beforeLoad: ({ location }) => {
		if (shouldBlockTVRoute(location.pathname, location.searchStr)) {
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: tvRouteRedirectTarget(location.pathname) });
		}
	},
	component: () => <Outlet />,
});
