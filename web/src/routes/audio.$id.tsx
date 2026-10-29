import { createFileRoute } from "@tanstack/react-router";
import { AudioDetailPage } from "../features/audio/AudioDetailPage";

export const Route = createFileRoute("/audio/$id")({
	component: AudioDetailPage,
});
