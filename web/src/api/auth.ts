// Совместимый реэкспорт: auth-контракт живёт в @flux/shared.
export type {
	AuthUser,
	RequestCodeResponse,
	VerifyCodeResponse,
} from "@flux/shared";
export {
	fetchMe,
	logout,
	requestCode,
	verifyCode,
} from "@flux/shared";
