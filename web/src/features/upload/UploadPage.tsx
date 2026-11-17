import {
	Alert,
	Button,
	Card,
	FileButton,
	Group,
	Loader,
	NumberInput,
	SegmentedControl,
	Select,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { ArrowLeft, FolderPlus, Upload, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useFranchises, useWork, useWorks } from "../../api/catalog";
import { useCollections } from "../../api/collections";
import { useSession } from "../../api/session";
import type { UploadType } from "../../api/upload";
import { CreateCollectionModal } from "../collections/CreateCollectionModal";
import { LEGACY_COLLECTIONS_ENABLED } from "../collections/legacy";
import { TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { LinkDownloadCard } from "./LinkDownloadCard";
import { UploadItemCard } from "./UploadItemCard";
import { type UploadTarget, useUploadQueue } from "./useUploadQueue";

const ACCEPT: Record<UploadType, string> = {
	video: ".mp4,.m4v,.mkv,.avi,.mov,.wmv,.webm,.flv,.ts",
	audio: ".mp3,.flac,.ogg,.oga,.m4a,.aac,.wav,.opus,.wma",
	image: ".jpg,.jpeg,.png,.gif,.webp,.bmp",
};

const TYPE_LABEL_KEYS: Record<UploadType, string> = {
	video: "upload.type.video",
	audio: "upload.type.audio",
	image: "upload.type.image",
};

const UPLOAD_TYPES: UploadType[] = ["video", "audio", "image"];

// eslint-disable-next-line max-lines-per-function, complexity -- форма загрузки с назначением.
export function UploadPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const search = useSearch({ from: "/upload" });
	const session = useSession();
	const type = search.type;
	// Коллекция для всей пачки (как во Flutter): смена типа сбрасывает
	// выбор, коллекция чужого типа файлам не достанется.
	const [collectionId, setCollectionId] = useState<number | null>(null);
	const [targetKind, setTargetKind] = useState<
		"standalone" | "series" | "film_series" | "franchise"
	>("standalone");
	const [targetWorkID, setTargetWorkID] = useState<string | null>(null);
	const [targetSeasonID, setTargetSeasonID] = useState<string | null>(null);
	const [targetEpisode, setTargetEpisode] = useState<string | number>("");
	const [targetFranchiseID, setTargetFranchiseID] = useState<string | null>(
		null,
	);
	const works = useWorks("series");
	const filmSeries = useWorks("film_series");
	const franchises = useFranchises();
	const selectedWork = useWork(
		Number(targetWorkID ?? 0),
		targetWorkID !== null,
	);
	const uploadTarget: UploadTarget =
		targetKind === "series" && targetWorkID !== null && targetSeasonID !== null
			? {
					kind: "series",
					workID: Number(targetWorkID),
					seasonID: Number(targetSeasonID),
					episodeNumber:
						targetEpisode === ""
							? undefined
							: Number.parseInt(String(targetEpisode), 10) || undefined,
				}
			: targetKind === "film_series" && targetWorkID !== null
				? { kind: "film_series", workID: Number(targetWorkID) }
				: targetKind === "franchise" && targetFranchiseID !== null
					? { kind: "franchise", franchiseID: Number(targetFranchiseID) }
					: { kind: "standalone" };
	const [createOpened, setCreateOpened] = useState(false);
	const collections = useCollections(LEGACY_COLLECTIONS_ENABLED);
	const {
		items,
		addFiles,
		cancelItem,
		removeItem,
		retryItem,
		forceItem,
		busy,
	} = useUploadQueue(type, collectionId, uploadTarget);
	// ТВ-режим: корень страницы — spatial-секция, форма внутри —
	// контент секции.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("upload-page");

	const changeType = (value: string) => {
		const next = value as UploadType;
		setCollectionId(null);
		void navigate({ to: "/upload", search: { type: next }, replace: true });
	};

	const matchingCollections = (collections.data ?? []).filter(
		(collection) => collection.type === type,
	);
	const selectedCollection =
		collectionId === null
			? null
			: (matchingCollections.find((item) => item.id === collectionId) ?? null);

	const goBack = () => {
		if (type === "video") {
			void navigate({ to: "/video" });
		} else if (type === "audio") {
			void navigate({ to: "/audio" });
		} else {
			void navigate({ to: "/memes" });
		}
	};

	if (session.isPending) {
		return (
			<Group justify="center" py="xl">
				<Loader />
			</Group>
		);
	}

	if (session.data?.is_admin !== true) {
		return (
			<Stack gap="md">
				<Alert color="red" variant="light">
					{t("upload.adminOnly")}
				</Alert>
				<Button variant="light" w="fit-content" onClick={goBack}>
					{t("upload.back")}
				</Button>
			</Stack>
		);
	}

	return (
		<Stack
			gap="lg"
			maw={960}
			mx="auto"
			w="100%"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="upload-page"
		>
			<TVFocusScope focusKey="upload-page">
				<Group justify="space-between" wrap="wrap">
					<Button
						variant="subtle"
						leftSection={<ArrowLeft size={16} />}
						onClick={goBack}
					>
						{t("upload.back")}
					</Button>
				</Group>

				<Stack gap={4}>
					<Title order={1} size="h2">
						{t("upload.title")}
					</Title>
					<Text c="dimmed">{t("upload.subtitle")}</Text>
				</Stack>

				<SegmentedControl
					value={type}
					onChange={changeType}
					disabled={busy}
					data={UPLOAD_TYPES.map((value) => ({
						value,
						label: t(TYPE_LABEL_KEYS[value]),
					}))}
					w="fit-content"
				/>

				{type === "video" && (
					<Card withBorder padding="md" radius="md">
						<Stack gap="sm">
							<Text fw={600}>{t("upload.target.title")}</Text>
							<Select
								label={t("upload.target.label")}
								value={targetKind}
								onChange={(value) => {
									setTargetKind(
										value === "series" ||
											value === "film_series" ||
											value === "franchise"
											? value
											: "standalone",
									);
									setTargetWorkID(null);
									setTargetSeasonID(null);
									setTargetFranchiseID(null);
								}}
								data={[
									{ value: "standalone", label: t("upload.target.standalone") },
									{ value: "series", label: t("catalog.seriesOne") },
									{ value: "film_series", label: t("catalog.filmSeries") },
									{ value: "franchise", label: t("catalog.franchise") },
								]}
							/>
							{targetKind === "series" && (
								<>
									<Select
										label={t("catalog.seriesOne")}
										data={(works.data ?? []).map((work) => ({
											value: String(work.id),
											label: work.title,
										}))}
										value={targetWorkID}
										onChange={(value) => {
											setTargetWorkID(value);
											setTargetSeasonID(null);
										}}
										searchable
									/>
									<Select
										label={t("catalog.seasonLabel")}
										data={(selectedWork.data?.seasons ?? []).map((season) => ({
											value: String(season.id),
											label:
												season.title ||
												t("catalog.season", { number: season.season_number }),
										}))}
										value={targetSeasonID}
										onChange={setTargetSeasonID}
									/>
									<NumberInput
										label={t("catalog.episodeNumber")}
										value={targetEpisode}
										onChange={setTargetEpisode}
										min={1}
									/>
								</>
							)}
							{targetKind === "film_series" && (
								<Select
									label={t("catalog.filmSeries")}
									data={(filmSeries.data ?? []).map((work) => ({
										value: String(work.id),
										label: work.title,
									}))}
									value={targetWorkID}
									onChange={setTargetWorkID}
									searchable
								/>
							)}
							{targetKind === "franchise" && (
								<Select
									label={t("catalog.franchise")}
									data={(franchises.data ?? []).map((franchise) => ({
										value: String(franchise.id),
										label: franchise.name,
									}))}
									value={targetFranchiseID}
									onChange={setTargetFranchiseID}
									searchable
								/>
							)}
						</Stack>
					</Card>
				)}

				{LEGACY_COLLECTIONS_ENABLED && (
					<>
						<Group gap="xs" wrap="wrap">
							<Select
								label={t("upload.collection")}
								placeholder={t("upload.collectionPlaceholder")}
								value={
									selectedCollection === null ? null : String(collectionId)
								}
								data={matchingCollections.map((collection) => ({
									value: String(collection.id),
									label: collection.name,
								}))}
								allowDeselect={false}
								disabled={collections.isPending}
								w={{ base: "100%", sm: 280 }}
								onChange={(value) => {
									setCollectionId(value === null ? null : Number(value));
								}}
							/>
							{selectedCollection !== null && (
								<Button
									variant="subtle"
									color="red"
									leftSection={<X size={16} />}
									onClick={() => setCollectionId(null)}
								>
									{t("upload.collectionClear")}
								</Button>
							)}
							<Button
								variant="light"
								leftSection={<FolderPlus size={16} />}
								onClick={() => setCreateOpened(true)}
							>
								{t("collections.create")}
							</Button>
						</Group>
						{selectedCollection !== null && (
							<Text size="sm" c="dimmed">
								{t("upload.collectionHint", { name: selectedCollection.name })}
							</Text>
						)}
					</>
				)}

				<FileButton onChange={addFiles} accept={ACCEPT[type]} multiple>
					{(props) => (
						<Button
							{...props}
							variant="light"
							leftSection={<Upload size={16} />}
							w="fit-content"
						>
							{t("upload.chooseFiles", { type: t(TYPE_LABEL_KEYS[type]) })}
						</Button>
					)}
				</FileButton>

				<LinkDownloadCard key={type} type={type} />

				{items.length === 0 ? (
					<Card withBorder padding="xl" radius="md">
						<Stack align="center" gap="sm">
							<Upload
								size={40}
								className="text-[var(--mantine-color-dimmed)]"
							/>
							<Text c="dimmed" ta="center">
								{t("upload.empty")}
							</Text>
						</Stack>
					</Card>
				) : (
					<Stack gap="sm">
						{items.map((item) => (
							<UploadItemCard
								key={item.key}
								item={item}
								onCancel={() => cancelItem(item)}
								onRemove={() => removeItem(item)}
								onRetry={() => retryItem(item)}
								onForce={() => forceItem(item)}
							/>
						))}
					</Stack>
				)}
			</TVFocusScope>
			<CreateCollectionModal
				opened={createOpened}
				type={type}
				onClose={() => setCreateOpened(false)}
				onCreated={(id) => setCollectionId(id)}
			/>
		</Stack>
	);
}
