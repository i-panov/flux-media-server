import {
	closestCenter,
	DndContext,
	type DragEndEvent,
	KeyboardSensor,
	PointerSensor,
	useSensor,
	useSensors,
} from "@dnd-kit/core";
import {
	arrayMove,
	SortableContext,
	sortableKeyboardCoordinates,
	useSortable,
	verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ActionIcon, Group } from "@mantine/core";
import { GripVertical } from "lucide-react";
import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";

function Row({
	id,
	disabled,
	children,
}: {
	id: number;
	disabled: boolean;
	children: ReactNode;
}) {
	const { t } = useTranslation();
	const { attributes, listeners, setNodeRef, transform, transition } =
		useSortable({ id, disabled });
	return (
		<div
			ref={setNodeRef}
			style={{ transform: CSS.Transform.toString(transform), transition }}
		>
			<Group gap="xs" wrap="nowrap" align="center">
				<ActionIcon
					variant="subtle"
					aria-label={t("catalog.admin.drag")}
					style={{ touchAction: "none" }}
					{...attributes}
					{...listeners}
					disabled={disabled}
				>
					<GripVertical size={16} />
				</ActionIcon>
				<div className="min-w-0 flex-1">{children}</div>
			</Group>
		</div>
	);
}

export function SortableList({
	ids,
	onReorder,
	children,
	disabled = false,
}: {
	ids: number[];
	onReorder: (ids: number[]) => void;
	children: (id: number) => ReactNode;
	disabled?: boolean;
}) {
	const sensors = useSensors(
		useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
		useSensor(KeyboardSensor, {
			coordinateGetter: sortableKeyboardCoordinates,
		}),
	);
	const handleDragEnd = (event: DragEndEvent) => {
		const { active, over } = event;
		if (over === null || active.id === over.id) return;
		const oldIndex = ids.indexOf(Number(active.id));
		const newIndex = ids.indexOf(Number(over.id));
		if (oldIndex < 0 || newIndex < 0) return;
		onReorder(arrayMove(ids, oldIndex, newIndex));
	};
	return (
		<DndContext
			sensors={sensors}
			collisionDetection={closestCenter}
			onDragEnd={handleDragEnd}
		>
			<SortableContext items={ids} strategy={verticalListSortingStrategy}>
				{ids.map((id) => (
					<Row key={id} id={id} disabled={disabled}>
						{children(id)}
					</Row>
				))}
			</SortableContext>
		</DndContext>
	);
}
