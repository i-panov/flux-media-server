import { createFileRoute, redirect } from "@tanstack/react-router";
import { z } from "zod";
import { sessionQueryOptions } from "../api/session";
import { LoginPage } from "../features/auth/LoginPage";

export const Route = createFileRoute("/login")({
	validateSearch: z.object({ redirect: z.string().optional() }),
	beforeLoad: async ({ context }) => {
		const session = await context.queryClient.ensureQueryData(
			sessionQueryOptions(),
		);
		if (session !== null) {
			// TanStack Router управляет редиректами брошенными объектами,
			// а не Error: точечно гасим only-throw-error.
			// eslint-disable-next-line @typescript-eslint/only-throw-error
			throw redirect({ to: "/" });
		}
	},
	component: LoginPage,
});
