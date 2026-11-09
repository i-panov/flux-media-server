import { createFileRoute, redirect } from "@tanstack/react-router";
import { sessionQueryOptions } from "../api/session";
import { AdminPage } from "../features/admin/AdminPage";

export const Route = createFileRoute("/admin")({
	beforeLoad: async ({ context }) => {
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
