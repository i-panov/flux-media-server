import { createFileRoute } from "@tanstack/react-router";
import { AudioPage } from "../features/audio/AudioPage";

export const Route = createFileRoute("/audio/")({
	component: AudioPage,
});
