import { createFileRoute } from "@tanstack/react-router";
import { SeriesPage } from "../features/catalog/SeriesPage";

export const Route = createFileRoute("/series/")({ component: SeriesPage });
