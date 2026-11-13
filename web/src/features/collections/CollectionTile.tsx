import { Card, Stack, Text } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Folder } from "lucide-react";
import { useId } from "react";
import type { Collection } from "../../api/collections";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

export function CollectionTile({ collection }: { collection: Collection }) {
	// ТВ-режим: плитка — spatial-цель, Enter повторяет клик по ссылке.
	const instanceKey = useId().replace(/:/g, "");
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`collection-tile-${collection.id}-${instanceKey}`,
		clickFirstLink,
	);
	return (
		<div ref={tvRef} tabIndex={tvMode ? -1 : undefined}>
			<Link
				to="/collections/$id"
				params={{ id: String(collection.id) }}
				className="no-underline [color:inherit]"
			>
				<Card withBorder padding="md" radius="md" h="100%">
					<Stack gap="xs" align="center">
						<Folder
							size={28}
							className="text-[var(--mantine-color-violet-5)]"
						/>
						<Text size="sm" fw={600} ta="center" lineClamp={2}>
							{collection.name}
						</Text>
					</Stack>
				</Card>
			</Link>
		</div>
	);
}
