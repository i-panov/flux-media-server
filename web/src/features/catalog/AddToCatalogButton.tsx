import {
	Alert,
	Button,
	Group,
	Modal,
	NumberInput,
	ScrollArea,
	Select,
	SimpleGrid,
	Stack,
	Text,
	TextInput,
	UnstyledButton,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useNavigate } from "@tanstack/react-router";
import { FolderPlus } from "lucide-react";
import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	useAddEpisode,
	useAddFilm,
	useMediaCatalogContext,
	useWork,
	useWorks,
	type WorkKind,
} from "../../api/catalog";
import type { Media } from "../../core/media";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";

type TargetKind = "series" | "film_series";

function WorkOption({
	title,
	year,
	selected,
	onClick,
}: {
	title: string;
	year: number;
	selected: boolean;
	onClick: () => void;
}) {
	return (
		<UnstyledButton
			onClick={onClick}
			aria-pressed={selected}
			className="w-full rounded-md border p-3 text-left"
			style={{
				// Инлайн: Mantine задаёт background-color для UnstyledButton
				// вне Tailwind-слоёв, и utility-класс проигрывает.
				backgroundColor: selected
					? "var(--mantine-color-violet-light)"
					: undefined,
				borderColor: selected ? "var(--mantine-color-violet-5)" : undefined,
			}}
		>
			<Text fw={600} lineClamp={2}>
				{title}
			</Text>
			{year > 0 && (
				<Text size="xs" c="dimmed">
					{year}
				</Text>
			)}
		</UnstyledButton>
	);
}

function WorkPicker({
	kind,
	selected,
	excludeID,
	onSelect,
}: {
	kind: WorkKind;
	selected: number | null;
	excludeID?: number;
	onSelect: (id: number) => void;
}) {
	const { t } = useTranslation();
	const works = useWorks(kind);
	const [search, setSearch] = useState("");
	const query = useDebouncedValue(search);
	const rows = useMemo(() => {
		const all = works.data ?? [];
		const needle = query.trim().toLocaleLowerCase();
		const visible =
			excludeID === undefined
				? all
				: all.filter((work) => work.id !== excludeID);
		return needle === ""
			? visible
			: visible.filter((work) =>
					work.title.toLocaleLowerCase().includes(needle),
				);
	}, [works.data, query, excludeID]);

	return (
		<Stack gap="xs">
			<TextInput
				value={search}
				onChange={(event) => setSearch(event.currentTarget.value)}
				placeholder={t("catalog.admin.searchWorks")}
			/>
			{works.isPending ? (
				<Text size="sm" c="dimmed">
					{t("common.loading")}
				</Text>
			) : works.isError ? (
				<Alert color="red">{t("catalog.error")}</Alert>
			) : rows.length === 0 ? (
				<Text size="sm" c="dimmed">
					{t("catalog.emptySeries")}
				</Text>
			) : (
				<ScrollArea.Autosize mah={260}>
					<SimpleGrid cols={2} spacing="xs">
						{rows.map((work) => (
							<WorkOption
								key={work.id}
								title={work.title}
								year={work.year}
								selected={selected === work.id}
								onClick={() => onSelect(work.id)}
							/>
						))}
					</SimpleGrid>
				</ScrollArea.Autosize>
			)}
			{selected !== null && (
				<Text size="xs" c="dimmed">
					{t("catalog.admin.selectedWork", {
						title:
							works.data?.find((work) => work.id === selected)?.title ?? "",
					})}
				</Text>
			)}
		</Stack>
	);
}

export function AddToCatalogButton({ media }: { media: Media }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const [opened, setOpened] = useState(false);
	const [kind, setKind] = useState<TargetKind>("series");
	const [workID, setWorkID] = useState<number | null>(null);
	const [seasonID, setSeasonID] = useState<string | null>(null);
	const [episode, setEpisode] = useState<string | number>("");
	const work = useWork(workID ?? 0, workID !== null);
	const addEpisode = useAddEpisode();
	const addFilm = useAddFilm();
	const context = useMediaCatalogContext(media.id);
	const excludeID = context.data?.work_id;
	const pending = addEpisode.isPending || addFilm.isPending;
	const seasons = work.data?.seasons ?? [];
	const season = seasons.find((row) => String(row.id) === seasonID);

	const reset = () => {
		setWorkID(null);
		setSeasonID(null);
		setEpisode("");
	};

	const changeKind = (value: string | null) => {
		setKind(value === "film_series" ? "film_series" : "series");
		reset();
	};

	const submit = async () => {
		if (workID === null) return;
		try {
			if (kind === "series") {
				if (season === undefined) return;
				const number =
					episode === "" ? undefined : Number.parseInt(String(episode), 10);
				await addEpisode.mutateAsync({
					seasonID: season.id,
					mediaID: media.id,
					episodeNumber:
						number === undefined || Number.isNaN(number) ? undefined : number,
				});
			} else {
				await addFilm.mutateAsync({ workID, mediaID: media.id });
			}
			notifications.show({
				message: t("catalog.admin.addedToCatalog"),
				color: "green",
			});
			setOpened(false);
			reset();
		} catch {
			notifications.show({
				message: t("catalog.addError"),
				color: "red",
			});
		}
	};

	return (
		<>
			<Button
				variant="light"
				leftSection={<FolderPlus size={16} />}
				onClick={() => setOpened(true)}
			>
				{t("catalog.addToCatalog")}
			</Button>
			<Modal
				opened={opened}
				onClose={() => {
					setOpened(false);
					reset();
				}}
				title={t("catalog.addToCatalog")}
				size="lg"
				centered
			>
				<Stack gap="md">
					<Select
						label={t("catalog.target")}
						value={kind}
						onChange={changeKind}
						data={[
							{ value: "series", label: t("catalog.seriesOne") },
							{ value: "film_series", label: t("catalog.filmSeries") },
						]}
					/>
					<WorkPicker
						kind={kind}
						selected={workID}
						excludeID={excludeID}
						onSelect={(id) => {
							setWorkID(id);
							setSeasonID(null);
						}}
					/>
					{kind === "series" && workID !== null && (
						<>
							<Select
								label={t("catalog.seasonLabel")}
								value={seasonID}
								onChange={setSeasonID}
								data={seasons.map((row) => ({
									value: String(row.id),
									label:
										row.title ||
										t("catalog.season", { number: row.season_number }),
								}))}
							/>
							<NumberInput
								label={t("catalog.episodeNumber")}
								value={episode}
								onChange={setEpisode}
								min={1}
								allowDecimal={false}
							/>
						</>
					)}
					<Group justify="space-between">
						{workID !== null && (
							<Button
								variant="subtle"
								onClick={() =>
									void navigate({
										to: "/series/$id",
										params: { id: String(workID) },
									})
								}
							>
								{t("catalog.openWork")}
							</Button>
						)}
						<Group>
							<Button
								variant="default"
								onClick={() => {
									setOpened(false);
									reset();
								}}
							>
								{t("common.cancel")}
							</Button>
							<Button
								loading={pending}
								disabled={
									workID === null || (kind === "series" && season === undefined)
								}
								onClick={() => void submit()}
							>
								{t("common.add")}
							</Button>
						</Group>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}
