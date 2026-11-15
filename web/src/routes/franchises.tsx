import { createFileRoute, Outlet } from "@tanstack/react-router";

export const Route = createFileRoute("/franchises")({
	component: () => <Outlet />,
});
