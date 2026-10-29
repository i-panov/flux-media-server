import { createFileRoute } from "@tanstack/react-router";
import { MemesPage } from "../features/memes/MemesPage";

export const Route = createFileRoute("/memes/")({
	component: MemesPage,
});
