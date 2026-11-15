import { createFileRoute } from "@tanstack/react-router";
import { FranchisesPage } from "../features/catalog/FranchisesPage";

export const Route = createFileRoute("/franchises/")({
	component: FranchisesPage,
});
