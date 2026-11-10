// Строки корзины Task 18 вынесены из index.ts: общий файл иначе
// приближается к лимиту max-lines. Английский объект типизирован по
// ключам русского, поэтому пропущенный перевод не соберётся.
export const trashRu = {
	"trash.title": "Корзина",
	"trash.empty": "Корзина пуста",
	"trash.emptyHint": "Удалённые медиа и коллекции появятся здесь.",
	"trash.collections": "Коллекции",
	"trash.media": "Медиа",
	"trash.restoreNamed": "Восстановить «{{title}}»",
	"trash.purge": "Удалить навсегда",
	"trash.purgeNamed": "Удалить навсегда «{{title}}»",
	"trash.emptyAction": "Очистить корзину",
	"trash.emptyTitle": "Очистить корзину?",
	"trash.emptyConfirm":
		"Все удалённые медиа и свои коллекции будут стёрты без возможности восстановления.",
	"trash.purgeTitle": "Удалить навсегда?",
	"trash.purgeMediaConfirm":
		"Медиа «{{title}}» и его файлы будут удалены без возможности восстановления.",
	"trash.purgeCollectionConfirm":
		"Коллекция «{{name}}» будет удалена вместе с подколлекциями и связями без возможности восстановления.",
	"trash.loadError": "Не удалось загрузить корзину",
	"trash.actionError": "Не удалось выполнить действие",
	"trash.missingError": "Объект уже не в корзине — список обновлён.",
	"trash.conflictError":
		"Файл недоступен или на его месте уже есть другое медиа.",
	"trash.forbiddenError": "Недостаточно прав для этого действия.",
	"trash.adminOnlyMedia":
		"Восстанавливать и удалять медиа может только администратор.",
} as const;

export const trashEn: Record<keyof typeof trashRu, string> = {
	"trash.title": "Trash",
	"trash.empty": "Trash is empty",
	"trash.emptyHint": "Deleted media and collections will appear here.",
	"trash.collections": "Collections",
	"trash.media": "Media",
	"trash.restoreNamed": 'Restore "{{title}}"',
	"trash.purge": "Delete permanently",
	"trash.purgeNamed": 'Delete permanently "{{title}}"',
	"trash.emptyAction": "Empty trash",
	"trash.emptyTitle": "Empty trash?",
	"trash.emptyConfirm":
		"All deleted media and your collections will be permanently removed.",
	"trash.purgeTitle": "Delete permanently?",
	"trash.purgeMediaConfirm":
		'Media "{{title}}" and its files will be permanently deleted.',
	"trash.purgeCollectionConfirm":
		'Collection "{{name}}" will be permanently deleted together with its subcollections and links.',
	"trash.loadError": "Could not load the trash",
	"trash.actionError": "Could not perform the action",
	"trash.missingError":
		"The item is no longer in the trash — the list was refreshed.",
	"trash.conflictError":
		"The file is unavailable or another media already uses its path.",
	"trash.forbiddenError": "You do not have permission for this action.",
	"trash.adminOnlyMedia": "Only an administrator can restore or delete media.",
};
