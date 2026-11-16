/* eslint-disable max-lines-per-function */
import {
	Alert,
	Button,
	Card,
	Group,
	Modal,
	Select,
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
	type CatalogFranchise,
	useAddFranchiseEntry,
	useDeleteFranchise,
	useRemoveFranchiseEntry,
	useReorderFranchiseEntries,
	useUpdateFranchise,
	useWorks,
} from "../../../api/catalog";
import { useSession } from "../../../api/session";
import { useTVMode } from "../../tv/useTVMode";
import { MediaPicker } from "./MediaPicker";
import { SortableList } from "./SortableList";

export function FranchiseAdminPanel({
	franchise,
}: {
	franchise: CatalogFranchise;
}) {
	const { t } = useTranslation();
	const session = useSession();
	const { capabilities } = useTVMode();
	const navigate = useNavigate();
	const isAdmin = session.data?.is_admin === true;
	const canManage = isAdmin && capabilities.canAccessAdmin;
	const works = useWorks(undefined, canManage);
	const update = useUpdateFranchise();
	const remove = useDeleteFranchise();
	const addEntry = useAddFranchiseEntry();
	const removeEntry = useRemoveFranchiseEntry();
	const reorder = useReorderFranchiseEntries();
	const [error, setError] = useState<string | null>(null);
	const [editOpen, setEditOpen] = useState(false);
	const [name, setName] = useState(franchise.name);
	const [description, setDescription] = useState(franchise.description);
	const [coverURL, setCoverURL] = useState(franchise.cover_url);
	const [addOpen, setAddOpen] = useState(false);
	const [target, setTarget] = useState<"work" | "media">("work");
	const [workID, setWorkID] = useState<string | null>(null);
	const [mediaID, setMediaID] = useState<string | null>(null);

	if (!isAdmin || !capabilities.canAccessAdmin) return null;
	const run = async (action: () => Promise<unknown>) => {
		setError(null);
		try {
			await action();
		} catch (err) {
			setError(err instanceof Error ? err.message : t("catalog.admin.error"));
		}
	};
	const workData = (works.data ?? []).map((work) => ({
		value: String(work.id),
		label: `${work.title} (${work.kind === "series" ? t("catalog.admin.series") : t("catalog.admin.filmSeries")})`,
	}));

	return (
		<Stack gap="md">
			<Title order={2} size="h4">
				{t("catalog.admin.manageFranchise")}
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
						if (window.confirm(t("catalog.admin.deleteFranchiseConfirm"))) {
							void run(async () => {
								await remove.mutateAsync(franchise.id);
								await navigate({ to: "/video", replace: true });
							});
						}
					}}
				>
					{t("catalog.admin.delete")}
				</Button>
				<Button onClick={() => setAddOpen(true)}>
					{t("catalog.admin.addEntry")}
				</Button>
			</Group>
			<SortableList
				disabled={reorder.isPending}
				ids={(franchise.entries ?? []).map((entry) => entry.id)}
				onReorder={(ids) =>
					void run(() =>
						reorder.mutateAsync({ franchiseID: franchise.id, ids }),
					)
				}
			>
				{(id) => {
					const entry = franchise.entries?.find((row) => row.id === id);
					if (!entry) return null;
					const title = entry.work?.title || entry.media?.title || `#${id}`;
					return (
						<Card withBorder padding="xs" radius="md">
							<Group justify="space-between" wrap="nowrap">
								<Text size="sm" lineClamp={1}>
									{title}
								</Text>
								<Button
									size="compact-xs"
									color="red"
									variant="subtle"
									aria-label={`${t("catalog.admin.remove")}: ${title}`}
									leftSection={<Trash2 size={14} />}
									onClick={() =>
										void run(() =>
											removeEntry.mutateAsync({
												franchiseID: franchise.id,
												entryID: entry.id,
											}),
										)
									}
								/>
							</Group>
						</Card>
					);
				}}
			</SortableList>

			<Modal
				opened={editOpen}
				onClose={() => setEditOpen(false)}
				title={t("catalog.admin.editFranchise")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<TextInput
						label={t("catalog.admin.name")}
						value={name}
						onChange={(event) => setName(event.currentTarget.value)}
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
					<Button
						onClick={() =>
							void run(async () => {
								await update.mutateAsync({
									id: franchise.id,
									name: name.trim(),
									description,
									cover_url: coverURL,
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
				opened={addOpen}
				onClose={() => {
					setAddOpen(false);
					setWorkID(null);
					setMediaID(null);
					setTarget("work");
				}}
				title={t("catalog.admin.addToFranchise")}
			>
				<Stack>
					{error && <Alert color="red">{error}</Alert>}
					<Select
						label={t("catalog.admin.type")}
						data={[
							{ value: "work", label: t("catalog.admin.workTarget") },
							{ value: "media", label: t("catalog.admin.singleFilm") },
						]}
						value={target}
						onChange={(value) =>
							setTarget(value === "media" ? "media" : "work")
						}
					/>
					{target === "work" ? (
						<Select
							label={t("catalog.admin.chooseWork")}
							searchable
							data={workData}
							value={workID}
							onChange={setWorkID}
						/>
					) : (
						<MediaPicker
							label={t("catalog.admin.chooseFilm")}
							value={mediaID}
							onChange={setMediaID}
						/>
					)}
					<Button
						disabled={target === "work" ? workID === null : mediaID === null}
						onClick={() =>
							void run(async () => {
								await addEntry.mutateAsync({
									franchiseID: franchise.id,
									workID:
										target === "work" && workID ? Number(workID) : undefined,
									mediaID:
										target === "media" && mediaID ? Number(mediaID) : undefined,
								});
								setAddOpen(false);
								setWorkID(null);
								setMediaID(null);
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
