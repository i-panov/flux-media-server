import { createFileRoute } from "@tanstack/react-router";
import { MemeDetailPage } from "../features/memes/MemeDetailPage";

export const Route = createFileRoute("/memes/$id")({
	component: MemeDetailPage,
});
