import type { ClientProfile } from "./clientProfile";

// Возможности клиента — единый источник для скрытия write-поверхностей.
// Серверные права не меняются: это только UX, а не замена авторизации.
export interface ClientCapabilities {
	canUpload: boolean;
	canEditMetadata: boolean;
	canChangeCover: boolean;
	canDelete: boolean;
	canManageTrash: boolean;
	canDownload: boolean;
	canManageCollections: boolean;
	canAccessAdmin: boolean;
}

const READ_ONLY_CAPABILITIES: ClientCapabilities = {
	canUpload: false,
	canEditMetadata: false,
	canChangeCover: false,
	canDelete: false,
	canManageTrash: false,
	// Скачивание на ТВ — выгрузка файла на устройство, которого у пульта
	// нет; матрица roadmap прямо запрещает downloads/export.
	canDownload: false,
	canManageCollections: false,
	canAccessAdmin: false,
};

const FULL_CAPABILITIES: ClientCapabilities = {
	canUpload: true,
	canEditMetadata: true,
	canChangeCover: true,
	canDelete: true,
	canManageTrash: true,
	canDownload: true,
	canManageCollections: true,
	canAccessAdmin: true,
};

export function capabilitiesForTVMode(tvMode: boolean): ClientCapabilities {
	return tvMode ? READ_ONLY_CAPABILITIES : FULL_CAPABILITIES;
}

export function capabilitiesForProfile(
	profile: ClientProfile,
): ClientCapabilities {
	return capabilitiesForTVMode(profile.isTV);
}
