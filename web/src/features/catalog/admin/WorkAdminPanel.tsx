/* eslint-disable max-lines-per-function */
import {
	Alert,
	Button,
	Card,
	Group,
	Modal,
	NumberInput,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type CatalogItem,
	type CatalogSeason,
	type CatalogWork,
	useAddEpisode,
	useAddFilm,
	useCreateSeason,
	useDeleteSeason,
	useDeleteWork,
	useRemoveEpisode,
	useRemoveFilm,
	useReorderEpisodes,
	useReorderFilms,
	useReorderSeasons,
	useUpdateWork,
} from "../../../api/catalog";
import { useSession } from "../../../api/session";
import { useTVMode } from "../../tv/useTVMode";
import { MediaPicker } from "./MediaPicker";
import { SortableList } from "./SortableList";

export function WorkAdminPanel({ work }: { work: CatalogWork }) {
	const { t } = useTranslation();
	const session = useSession();
	const { capabilities } = useTVMode();
	const navigate = useNavigate();
	const isAdmin = session.data?.is_admin === true;
	const update = useUpdateWork();
	const removeWork = useDeleteWork();
	const createSeason = useCreateSeason();
	const deleteSeason = useDeleteSeason();
	const reorderSeasons = useReorderSeasons();
	const addEpisode = useAddEpisode();
	const removeEpisode = useRemoveEpisode();
	const reorderEpisodes = useReorderEpisodes();
	const addFilm = useAddFilm();
	const removeFilm = useRemoveFilm();
	const reorderFilms = useReorderFilms();
	const [error, setError] = useState<string | null>(null);
	const [editOpen, setEditOpen] = useState(false);
	const [title, setTitle] = useState(work.title);
	const [description, setDescription] = useState(work.description);
	const [coverURL, setCoverURL] = useState(work.cover_url);
	const [year, setYear] = useState<number | string>(work.year);
	const [seasonOpen, setSeasonOpen] = useState(false);
	const [seasonNumber, setSeasonNumber] = useState<number | string>(1);
	const [seasonTitle, setSeasonTitle] = useState("");
	const [episodeSeason, setEpisodeSeason] = useState<CatalogSeason | null>(
		null,
	);
	const [episodeMedia, setEpisodeMedia] = useState<string | null>(null);
	const [episodeNumber, setEpisodeNumber] = useState<number | string>("");
	const [filmOpen, setFilmOpen] = useState(false);
	const [filmMedia, setFilmMedia] = useState<string | null>(null);

	if (!isAdmin || !capabilities.canAccessAdmin) return null;

	const openSeason = () => {
		const next =
			Math.max(
				0,
				...(work.seasons ?? []).map((season) => season.season_number),
			) + 1;
		setSeasonNumber(next);
		setSeasonTitle("");
		setSeasonOpen(true);
	};

	const run = async (action: () => Promise<unknown>) => {
		setError(null);
		try {
			await action();
		} catch (err) {
			setError(err instanceof Error ? err.message : t("catalog.admin.error"));
		}
	};

	return (
		<Stack gap="md">
			<Title order={2} size="h4">
				{t("catalog.admin.manageWork")}
			</Title>
			{error && <Alert color="red">{error}</Alert>}
			<Group>
				<Button variant="default" onClick={() => setEditOpen(true)}>
					{t("catalog.admin.edit")}
				</Button>
				<Button
					color="red"
					variant="light"
					onClick={() => {
						if (window.confirm(t("catalog.admin.deleteWorkConfirm"))) {
							void run(async () => {
								await removeWork.mutateAsync(work.id);
								await navigate({ to: "/series", replace: true });
							});
						}
					}}
				>
					{t("catalog.admin.delete")}
				</Button>
			</Group>

			{work.kind === "series" ? (
				<Stack gap="sm">
					<Group justify="space-between">
						<Title order={3} size="h5">
							{t("catalog.admin.seasons")}
						</Title>
						<Button size="xs" onClick={openSeason}>
							{t("catalog.admin.addSeason")}
						</Button>
					</Group>
					{(work.seasons ?? []).length === 0 ? (
						<Text size="sm" c="dimmed">
							{t("catalog.admin.noSeasons")}
						</Text>
					) : (
						<SortableList
							disabled={reorderSeasons.isPending}
							ids={(work.seasons ?? []).map((season) => season.id)}
							onReorder={(ids) =>
								void run(() =>
									reorderSeasons.mutateAsync({ workID: work.id, ids }),
								)
							}
						>
							{(id) => {
								const season = work.seasons?.find((row) => row.id === id);
								if (!season) return null;
								return (
									<Card withBorder padding="xs" radius="md">
										<Group justify="space-between" wrap="nowrap">
											<Text fw={500}>
												{season.title ||
													t("catalog.season", { number: season.season_number })}
											</Text>
											<Group gap="xs">
												<Button
													size="compact-xs"
													variant="light"
													onClick={() => setEpisodeSeason(season)}
												>
													{t("catalog.admin.episode")}
												</Button>
												<Button
													size="compact-xs"
													color="red"
													variant="subtle"
													aria-label={`${t("catalog.admin.delete")}: ${season.title || t("catalog.season", { number: season.season_number })}`}
													disabled={(work.seasons ?? []).length <= 1}
													leftSection={<Trash2 size={14} />}
													onClick={() => {
														if (
															window.confirm(
																t("catalog.admin.deleteSeasonConfirm"),
															)
														) {
															void run(() =>
																deleteSeason.mutateAsync(season.id),
															);
														}
													}}
												/>
											</Group>
										</Group>
										{(season.items ?? []).length > 0 && (
											<Stack gap={4} mt="xs">
												<SortableList
													disabled={reorderEpisodes.isPending}
													ids={(season.items ?? []).map((item) => item.id)}
													onReorder={(ids) =>
														void run(() =>
															reorderEpisodes.mutateAsync({
																seasonID: season.id,
																ids,
															}),
														)
													}
												>
													{(itemID) => {
														const item = season.items?.find(
															(row) => row.id === itemID,
														);
														if (!item) return null;
														return (
															<Group justify="space-between" wrap="nowrap">
																<Text size="sm" lineClamp={1}>
																	{item.episode_number == null
																		? ""
																		: `${item.episode_number}. `}
																	{item.media?.title ?? `#${item.media_id}`}
																</Text>
																<Button
																	size="compact-xs"
																	color="red"
																	variant="subtle"
																	onClick={() =>
																		void run(() =>
																			removeEpisode.mutateAsync({
																				seasonID: season.id,
																				mediaID: item.media_id,
																			}),
																		)
																	}
																>
																	{t("catalog.admin.remove")}
																</Button>
															</Group>
														);
													}}
												</SortableList>
											</Stack>
										)}
									</Card>
								);
							}}
						</SortableList>
					)}
				</Stack>
			) : (
				<Stack gap="sm">
					<Group justify="space-between">
						<Title order={3} size="h5">
							{t("catalog.admin.films")}
						</Title>
						<Button size="xs" onClick={() => setFilmOpen(true)}>
							{t("catalog.admin.addFilm")}
						</Button>
					</Group>
					<SortableList
						disabled={reorderFilms.isPending}
						ids={(work.items ?? []).map((item) => item.id)}
						onReorder={(ids) =>
							void run(() => reorderFilms.mutateAsync({ workID: work.id, ids }))
						}
					>
						{(id) => {
							const item = work.items?.find(
								(row: CatalogItem) => row.id === id,
							);
							if (!item) return null;
							return (
								<Group justify="space-between" wrap="nowrap">
									<Text size="sm">
										{item.media?.title ?? `#${item.media_id}`}
									</Text>
									<Button
										size="compact-xs"
										color="red"
										variant="subtle"
										onClick={() =>
											void run(() =>
												removeFilm.mutateAsync({
													workID: work.id,
													mediaID: item.media_id,
												}),
											)
										}
									>
										{t("catalog.admin.remove")}
									</Button>
								</Group>
							);
						}}
					</SortableList>
				</Stack>
			)}

			<Modal
				opened={editOpen}
				onClose={() => setEditOpen(false)}
				title={t("catalog.admin.edit")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<TextInput
						label={t("catalog.admin.title")}
						value={title}
						onChange={(event) => setTitle(event.currentTarget.value)}
					/>
					<TextInput
						label={t("catalog.admin.description")}
						value={description}
						onChange={(event) => setDescription(event.currentTarget.value)}
					/>
					<TextInput
						label={t("catalog.admin.coverURL")}
						value={coverURL}
						onChange={(event) => setCoverURL(event.currentTarget.value)}
					/>
					<NumberInput
						label={t("catalog.admin.year")}
						value={year}
						onChange={setYear}
						min={0}
					/>
					<Button
						onClick={() =>
							void run(async () => {
								await update.mutateAsync({
									id: work.id,
									title: title.trim(),
									description,
									cover_url: coverURL,
									year: typeof year === "number" ? year : undefined,
								});
								setEditOpen(false);
							})
						}
					>
						{t("catalog.admin.save")}
					</Button>
				</Stack>
			</Modal>

			<Modal
				opened={seasonOpen}
				onClose={() => setSeasonOpen(false)}
				title={t("catalog.admin.newSeason")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<NumberInput
						label={t("catalog.admin.number")}
						value={seasonNumber}
						onChange={setSeasonNumber}
						min={0}
					/>
					<TextInput
						label={t("catalog.admin.title")}
						value={seasonTitle}
						onChange={(event) => setSeasonTitle(event.currentTarget.value)}
					/>
					<Button
						disabled={
							typeof seasonNumber !== "number" || createSeason.isPending
						}
						onClick={() =>
							void run(async () => {
								if (typeof seasonNumber !== "number") return;
								await createSeason.mutateAsync({
									workID: work.id,
									seasonNumber,
									title: seasonTitle.trim(),
								});
								setSeasonOpen(false);
							})
						}
					>
						{t("catalog.admin.create")}
					</Button>
				</Stack>
			</Modal>

			<Modal
				opened={episodeSeason !== null}
				onClose={() => {
					setEpisodeSeason(null);
					setEpisodeMedia(null);
					setEpisodeNumber("");
				}}
				title={t("catalog.admin.newEpisode")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<MediaPicker
						label={t("catalog.admin.video")}
						value={episodeMedia}
						onChange={setEpisodeMedia}
					/>
					<NumberInput
						label={t("catalog.admin.episodeNumber")}
						value={episodeNumber}
						onChange={setEpisodeNumber}
						min={0}
					/>
					<Button
						disabled={episodeMedia === null}
						onClick={() =>
							void run(async () => {
								if (episodeSeason === null || episodeMedia === null) return;
								await addEpisode.mutateAsync({
									seasonID: episodeSeason.id,
									mediaID: Number(episodeMedia),
									episodeNumber:
										typeof episodeNumber === "number"
											? episodeNumber
											: undefined,
								});
								setEpisodeSeason(null);
								setEpisodeMedia(null);
								setEpisodeNumber("");
							})
						}
					>
						{t("catalog.admin.add")}
					</Button>
				</Stack>
			</Modal>

			<Modal
				opened={filmOpen}
				onClose={() => {
					setFilmOpen(false);
					setFilmMedia(null);
				}}
				title={t("catalog.admin.newFilm")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<MediaPicker
						label={t("catalog.admin.video")}
						value={filmMedia}
						onChange={setFilmMedia}
					/>
					<Button
						disabled={filmMedia === null}
						onClick={() =>
							void run(async () => {
								if (filmMedia === null) return;
								await addFilm.mutateAsync({
									workID: work.id,
									mediaID: Number(filmMedia),
								});
								setFilmOpen(false);
								setFilmMedia(null);
							})
						}
					>
						{t("catalog.admin.add")}
					</Button>
				</Stack>
			</Modal>
		</Stack>
	);
}
