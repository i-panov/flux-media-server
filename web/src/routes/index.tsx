import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/")({
	beforeLoad: () => {
		// Отдельного «Главного» больше нет: корень ведёт на видео.
		// eslint-disable-next-line @typescript-eslint/only-throw-error
		throw redirect({ to: "/video" });
	},
});
