// Совместимый реэкспорт: auth-контракт живёт в @flux/shared.
export type {
	AuthUser,
	DeviceCodeResponse,
} from "@flux/shared";
export {
	approveDeviceCode,
	createDeviceCode,
	fetchDevices,
	fetchMe,
	inspectDeviceCode,
	logout,
	pollDeviceCode,
	requestCode,
	revokeDevice,
	verifyCode,
} from "@flux/shared";
