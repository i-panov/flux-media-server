import { createFileRoute, redirect } from "@tanstack/react-router";

// Отдельной страницы аудио нет: полный плеер — /player, мини-плеер
// открывается кликом по строке. Старые ссылки ведут в список.
export const Route = createFileRoute("/audio/$id")({
	beforeLoad: () => {
		// eslint-disable-next-line @typescript-eslint/only-throw-error
		throw redirect({ to: "/audio" });
	},
});
