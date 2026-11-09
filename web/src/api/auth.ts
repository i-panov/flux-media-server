// Совместимый реэкспорт: auth-контракт живёт в @flux/shared.
export type { AuthUser } from "@flux/shared";
export {
	fetchMe,
	logout,
	requestCode,
	verifyCode,
} from "@flux/shared";
