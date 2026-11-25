import { createFileRoute } from "@tanstack/react-router";
import { ArtistsPage } from "../features/audio/ArtistsPage";

export const Route = createFileRoute("/artists/")({
	component: ArtistsPage,
});
