import { createFileRoute } from "@tanstack/react-router";
import { SeriesDetailPage } from "../features/catalog/SeriesDetailPage";

export const Route = createFileRoute("/series/$id")({
	component: SeriesDetailRoute,
});

function SeriesDetailRoute() {
	const { id } = Route.useParams();
	const numeric = Number(id);
	if (!Number.isInteger(numeric) || numeric <= 0) {
		return <div className="p-4 text-[var(--mantine-color-dimmed)]">404</div>;
	}
	return <SeriesDetailPage id={numeric} />;
}
