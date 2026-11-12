import { createFileRoute } from "@tanstack/react-router";
import { ActivatePage } from "../features/auth/ActivatePage";

interface ActivateSearch {
	code?: string;
}

export const Route = createFileRoute("/activate")({
	validateSearch: (search: Record<string, unknown>): ActivateSearch => ({
		code: typeof search.code === "string" ? search.code : undefined,
	}),
	component: ActivatePage,
});
