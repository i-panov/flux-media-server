import {
	ActionIcon,
	Button,
	Group,
	Modal,
	Stack,
	Text,
	Textarea,
	TextInput,
} from "@mantine/core";
import { Plus, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useMediaArtists, useUpdateMetadata } from "../../api/metadata";
import type { Media } from "../../core/media";
import { useCollectionError } from "../collections/useCollectionError";

const YEAR_PATTERN = /^\d{4}$/;
const MIN_YEAR = 1888;

function isValidYear(value: string): boolean {
	const trimmed = value.trim();
	if (trimmed === "") {
		return true;
	}
	if (!YEAR_PATTERN.test(trimmed)) {
		return false;
	}
	const year = Number(trimmed);
	return year >= MIN_YEAR && year <= new Date().getFullYear() + 2;
}

function isValidSourceUrl(value: string): boolean {
	const trimmed = value.trim();
	if (trimmed === "") {
		return true;
	}
	try {
		const url = new URL(trimmed);
		return url.protocol === "http:" || url.protocol === "https:";
	} catch {
		return false;
	}
}

// Правка метаданных (название, исполнители, альбом, жанр, год, описание,
// ссылка): как во Flutter, при ошибке сети диалог остаётся открытым
// и введённое не теряется. Пустые необязательные поля не отправляются,
// source_url — только при изменении; пустое при непустом исходном это очистка.
export function EditMetadataModal({
	opened,
	media,
	onClose,
}: {
	opened: boolean;
	media: Media;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const notifyError = useCollectionError();
	const update = useUpdateMetadata(media.id);
	const artistNames = useMediaArtists();

	const [title, setTitle] = useState(media.title);
	const [artists, setArtists] = useState<string[]>(
		media.artists.length > 0
			? media.artists.map((artist) => artist.name)
			: [""],
	);
	const [album, setAlbum] = useState(media.album);
	const [genre, setGenre] = useState(media.genre);
	const [year, setYear] = useState(media.year > 0 ? String(media.year) : "");
	const [description, setDescription] = useState(media.description);
	const [sourceUrl, setSourceUrl] = useState(media.source_url);
	const originalSourceUrl = media.source_url;

	const titleError = title.trim() === "" ? t("metadata.required") : null;
	const yearError = isValidYear(year) ? null : t("metadata.invalidYear");
	const sourceError = isValidSourceUrl(sourceUrl)
		? null
		: t("metadata.invalidSourceUrl");
	const canSave =
		titleError === null && yearError === null && sourceError === null;

	const submit = () => {
		if (!canSave || update.isPending) {
			return;
		}
		const trimmedYear = year.trim();
		const trimmedSource = sourceUrl.trim();
		update.mutate(
			{
				title: title.trim(),
				artists: artists
					.map((name) => name.trim())
					.filter((name) => name !== ""),
				album: album.trim(),
				genre: genre.trim(),
				year: trimmedYear === "" ? undefined : Number(trimmedYear),
				description: description.trim(),
				// Ссылку шлём только при изменении (как во Flutter):
				// иначе каждое сохранение стирало бы выставленную
				// в другом клиенте ссылку пустой строкой.
				sourceUrl:
					trimmedSource === originalSourceUrl ? undefined : trimmedSource,
			},
			{ onSuccess: onClose, onError: notifyError },
		);
	};

	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("metadata.title")}
			centered
			size="lg"
		>
			<Stack gap="md">
				<TextInput
					label={t("metadata.name")}
					value={title}
					data-autofocus
					error={titleError}
					onChange={(event) => setTitle(event.currentTarget.value)}
				/>
				<Stack gap={4}>
					<Group justify="space-between">
						<Text size="sm" fw={500}>
							{t("metadata.artists")}
						</Text>
						<ActionIcon
							variant="subtle"
							aria-label={t("metadata.addArtist")}
							onClick={() => setArtists((prev) => [...prev, ""])}
						>
							<Plus size={16} />
						</ActionIcon>
					</Group>
					{artists.map((name, position) => (
						// Исполнители без id: порядок и есть идентификатор строки.
						// biome-ignore lint/suspicious/noArrayIndexKey: artist row
						<Group key={position} gap="xs" wrap="nowrap">
							<TextInput
								className="flex-1"
								value={name}
								list="metadata-artists"
								aria-label={`${t("metadata.artists")} ${position + 1}`}
								onChange={(event) =>
									setArtists((prev) =>
										prev.map((item, i) =>
											i === position ? event.currentTarget.value : item,
										),
									)
								}
							/>
							{artists.length > 1 && (
								<ActionIcon
									variant="subtle"
									color="red"
									aria-label={t("metadata.removeArtist")}
									onClick={() =>
										setArtists((prev) => prev.filter((_, i) => i !== position))
									}
								>
									<X size={16} />
								</ActionIcon>
							)}
						</Group>
					))}
					<datalist id="metadata-artists">
						{(artistNames.data ?? []).map((name) => (
							<option key={name} value={name} />
						))}
					</datalist>
				</Stack>
				<Group grow>
					<TextInput
						label={t("metadata.album")}
						value={album}
						onChange={(event) => setAlbum(event.currentTarget.value)}
					/>
					<TextInput
						label={t("metadata.genre")}
						value={genre}
						onChange={(event) => setGenre(event.currentTarget.value)}
					/>
				</Group>
				<Group grow>
					<TextInput
						label={t("metadata.year")}
						value={year}
						inputMode="numeric"
						error={yearError}
						onChange={(event) => setYear(event.currentTarget.value)}
					/>
					<TextInput
						label={t("metadata.sourceUrl")}
						value={sourceUrl}
						placeholder="https://"
						inputMode="url"
						error={sourceError}
						onChange={(event) => setSourceUrl(event.currentTarget.value)}
					/>
				</Group>
				<Textarea
					label={t("metadata.description")}
					value={description}
					autosize
					minRows={3}
					maxRows={8}
					onChange={(event) => setDescription(event.currentTarget.value)}
				/>
				{update.isError && (
					<Text size="sm" c="red">
						{t("metadata.saveError")}
					</Text>
				)}
				<Group justify="flex-end">
					<Button variant="default" onClick={onClose}>
						{t("collections.cancel")}
					</Button>
					<Button
						loading={update.isPending}
						disabled={!canSave}
						onClick={submit}
					>
						{t("collections.save")}
					</Button>
				</Group>
			</Stack>
		</Modal>
	);
}
