import { Card, Stack, Text } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Folder } from "lucide-react";
import type { Collection } from "../../api/collections";

export function CollectionTile({ collection }: { collection: Collection }) {
	return (
		<Link
			to="/collections/$id"
			params={{ id: String(collection.id) }}
			className="no-underline [color:inherit]"
		>
			<Card withBorder padding="md" radius="md" h="100%">
				<Stack gap="xs" align="center">
					<Folder size={28} className="text-[var(--mantine-color-violet-5)]" />
					<Text size="sm" fw={600} ta="center" lineClamp={2}>
						{collection.name}
					</Text>
				</Stack>
			</Card>
		</Link>
	);
}
