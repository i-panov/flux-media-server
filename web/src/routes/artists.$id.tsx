import { createFileRoute } from "@tanstack/react-router";
import { ArtistPage } from "../features/audio/ArtistPage";

export const Route = createFileRoute("/artists/$id")({
	component: ArtistPage,
});
