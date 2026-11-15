import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/series")({
	component: () => <Outlet />,
});
