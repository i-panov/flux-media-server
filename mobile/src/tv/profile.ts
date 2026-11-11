import { Platform } from "react-native";

// react-native-tvos выставляет Platform.isTV; на телефоне флаг false.
export const isTV = (Platform as unknown as { isTV?: boolean }).isTV === true;

export const tvCapabilities = {
	canUpload: !isTV,
	canEditMetadata: !isTV,
	canChangeCover: !isTV,
	canDelete: !isTV,
	canManageTrash: !isTV,
	canDownload: !isTV,
	canManageCollections: !isTV,
} as const;
