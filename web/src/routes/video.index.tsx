import { createFileRoute } from "@tanstack/react-router";
import { VideoPage } from "../features/video/VideoPage";

export const Route = createFileRoute("/video/")({
	component: VideoPage,
});
