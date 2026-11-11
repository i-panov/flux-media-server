import {
	ActionIcon,
	Badge,
	Button,
	Group,
	Menu,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import {
	ArrowLeft,
	FolderInput,
	MoreVertical,
	Pencil,
	Plus,
	Trash2,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import type { Collection } from "../../api/collections";
import { MEDIA_TYPE_LABEL_KEYS } from "../../components/mediaType";
import type { MediaType } from "../../core/media";
import { clickNode, useTVFocusable } from "../tv/tvFocus";
import { BACK_LABEL_KEY } from "./collectionUtils";

export function CollectionHeader({
	collection,
	type,
	count,
	backPath,
	parent,
	onAdd,
	onRename,
	onMove,
	onDelete,
	readOnly = false,
}: {
	collection: Collection;
	type: MediaType;
	count: number;
	backPath: "/video" | "/audio" | "/memes";
	parent?: Collection;
	onAdd: () => void;
	onRename: () => void;
	onMove: () => void;
	onDelete: () => void;
	readOnly?: boolean;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { targetRef: backRef } = useTVFocusable<HTMLButtonElement>(
		"collection-detail-back",
		clickNode,
	);
	const backLabel =
		parent === undefined
			? t(BACK_LABEL_KEY)
			: t("collections.backToParent", { name: parent.name });
	return (
		<Stack gap="xs">
			<Group justify="space-between" align="center" wrap="wrap">
				<Button
					ref={backRef}
					data-tv-focus-key="collection-detail-back"
					variant="subtle"
					leftSection={<ArrowLeft size={16} />}
					onClick={() => {
						if (parent === undefined) {
							void navigate({ to: backPath });
						} else {
							void navigate({
								to: "/collections/$id",
								params: { id: String(parent.id) },
							});
						}
					}}
				>
					{backLabel}
				</Button>
				{!readOnly && (
					<Group gap="xs">
						<Button
							variant="light"
							leftSection={<Plus size={16} />}
							onClick={onAdd}
						>
							{t("collections.addMedia")}
						</Button>
						<Menu position="bottom-end" withinPortal>
							<Menu.Target>
								<ActionIcon
									variant="default"
									size="lg"
									aria-label={t("collections.actions")}
								>
									<MoreVertical size={18} />
								</ActionIcon>
							</Menu.Target>
							<Menu.Dropdown>
								<Menu.Item
									leftSection={<Pencil size={14} />}
									onClick={onRename}
								>
									{t("collections.rename")}
								</Menu.Item>
								<Menu.Item
									leftSection={<FolderInput size={14} />}
									onClick={onMove}
								>
									{t("collections.moveCollection")}
								</Menu.Item>
								<Menu.Item
									color="red"
									leftSection={<Trash2 size={14} />}
									onClick={onDelete}
								>
									{t("collections.delete")}
								</Menu.Item>
							</Menu.Dropdown>
						</Menu>
					</Group>
				)}
			</Group>
			<Group gap="sm" wrap="wrap">
				<Title order={1} size="h2">
					{collection.name}
				</Title>
				<Badge variant="light" color="violet">
					{t(MEDIA_TYPE_LABEL_KEYS[type])}
				</Badge>
			</Group>
			<Text size="sm" c="dimmed">
				{t("collections.itemsCount", { count })}
			</Text>
		</Stack>
	);
}
