import {
	Alert,
	Button,
	Card,
	FileButton,
	Group,
	Loader,
	SegmentedControl,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { ArrowLeft, Upload } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useSession } from "../../api/session";
import type { UploadType } from "../../api/upload";
import { UploadItemCard } from "./UploadItemCard";
import { useUploadQueue } from "./useUploadQueue";

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

export function UploadPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const search = useSearch({ from: "/upload" });
	const session = useSession();
	const type = search.type;
	const {
		items,
		addFiles,
		cancelItem,
		removeItem,
		retryItem,
		forceItem,
		busy,
	} = useUploadQueue(type);

	const changeType = (value: string) => {
		const next = value as UploadType;
		void navigate({ to: "/upload", search: { type: next }, replace: true });
	};

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
		<Stack gap="lg" maw={960} mx="auto" w="100%">
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

			{items.length === 0 ? (
				<Card withBorder padding="xl" radius="md">
					<Stack align="center" gap="sm">
						<Upload size={40} className="text-[var(--mantine-color-dimmed)]" />
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
		</Stack>
	);
}
