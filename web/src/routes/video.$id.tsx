import { createFileRoute } from "@tanstack/react-router";
import { VideoDetailPage } from "../features/video/VideoDetailPage";

export const Route = createFileRoute("/video/$id")({
	component: VideoDetailPage,
});
