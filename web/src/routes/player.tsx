import { createFileRoute } from "@tanstack/react-router";
import { AudioPlayerPage } from "../features/player/AudioPlayerPage";

export const Route = createFileRoute("/player")({
	component: AudioPlayerPage,
});
