import { createFileRoute } from "@tanstack/react-router";
import { CollectionDetailPage } from "../features/collections/CollectionDetailPage";

export const Route = createFileRoute("/collections/$id")({
	component: CollectionDetailPage,
});
