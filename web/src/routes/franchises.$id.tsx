import { createFileRoute } from "@tanstack/react-router";
import { FranchiseDetailPage } from "../features/catalog/FranchiseDetailPage";

export const Route = createFileRoute("/franchises/$id")({
	component: FranchiseDetailRoute,
});

function FranchiseDetailRoute() {
	const { id } = Route.useParams();
	const numeric = Number(id);
	if (!Number.isInteger(numeric) || numeric <= 0) {
		return <div className="p-4 text-[var(--mantine-color-dimmed)]">404</div>;
	}
	return <FranchiseDetailPage id={numeric} />;
}
