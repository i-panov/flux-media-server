import { z } from "zod";
import { apiFetch } from "./client";

const authUserSchema = z.object({
	id: z.number(),
	email: z.string(),
	is_admin: z.boolean(),
});

export type AuthUser = z.infer<typeof authUserSchema>;

const requestCodeSchema = z.object({
	message: z.string(),
	// Код приходит только от сервера в debug-режиме.
	code: z.string().optional(),
});

export type RequestCodeResponse = z.infer<typeof requestCodeSchema>;

const tokenPairSchema = z.object({
	token: z.string(),
	refresh_token: z.string(),
});

const verifyCodeSchema = tokenPairSchema.extend({
	user: authUserSchema,
});

export type VerifyCodeResponse = z.infer<typeof verifyCodeSchema>;

export async function requestCode(email: string): Promise<RequestCodeResponse> {
	const body = await apiFetch<unknown>("/auth/request-code", {
		method: "POST",
		body: JSON.stringify({ email }),
	});
	return requestCodeSchema.parse(body);
}

export interface DeviceInfoInput {
	deviceId?: string;
	deviceName?: string;
	platform?: string;
}

export async function verifyCode(
	email: string,
	code: string,
	device?: DeviceInfoInput,
): Promise<VerifyCodeResponse> {
	const body = await apiFetch<unknown>("/auth/verify-code", {
		method: "POST",
		body: JSON.stringify({
			email,
			code,
			device_id: device?.deviceId ?? "",
			device_name: device?.deviceName ?? "",
			platform: device?.platform ?? "",
		}),
	});
	return verifyCodeSchema.parse(body);
}

export async function fetchMe(signal?: AbortSignal): Promise<AuthUser> {
	const body = await apiFetch<unknown>("/auth/me", { signal });
	return authUserSchema.parse(body);
}

export async function logout(refreshToken?: string): Promise<void> {
	await apiFetch<unknown>("/auth/logout", {
		method: "POST",
		body: JSON.stringify({ refresh_token: refreshToken ?? "" }),
	});
}

const deviceCodeSchema = z.object({
	device_code: z.string(),
	user_code: z.string(),
	verification_uri: z.string(),
	verification_uri_complete: z.string(),
	expires_in: z.number(),
	interval: z.number(),
});

export type DeviceCodeResponse = z.infer<typeof deviceCodeSchema>;

const devicePendingSchema = z.object({
	status: z.literal("pending"),
	interval: z.number(),
});

const deviceExpiredSchema = z.object({
	status: z.literal("expired"),
});

const deviceOkSchema = tokenPairSchema.extend({
	status: z.literal("ok"),
	user: authUserSchema,
});

export type DevicePollResponse =
	| z.infer<typeof devicePendingSchema>
	| z.infer<typeof deviceExpiredSchema>
	| z.infer<typeof deviceOkSchema>
	| { status: "invalid_grant" };

export async function createDeviceCode(input?: {
	deviceId?: string;
	deviceName?: string;
	platform?: string;
}): Promise<DeviceCodeResponse> {
	const body = await apiFetch<unknown>("/auth/device/code", {
		method: "POST",
		body: JSON.stringify({
			device_id: input?.deviceId ?? "",
			device_name: input?.deviceName ?? "",
			platform: input?.platform ?? "",
		}),
	});
	return deviceCodeSchema.parse(body);
}

export async function pollDeviceCode(
	deviceCode: string,
): Promise<DevicePollResponse> {
	const body = await apiFetch<unknown>("/auth/device/token", {
		method: "POST",
		body: JSON.stringify({ device_code: deviceCode }),
	});
	const status = (body as { status?: unknown }).status;
	if (status === "ok") return deviceOkSchema.parse(body);
	if (status === "pending") return devicePendingSchema.parse(body);
	if (status === "expired") return deviceExpiredSchema.parse(body);
	return { status: "invalid_grant" };
}

const deviceInspectSchema = z.object({
	device_name: z.string(),
	platform: z.string(),
	expires_at: z.string(),
});

export type DeviceInspectResponse = z.infer<typeof deviceInspectSchema>;

export async function inspectDeviceCode(
	userCode: string,
): Promise<DeviceInspectResponse> {
	const body = await apiFetch<unknown>("/auth/device/inspect", {
		method: "POST",
		body: JSON.stringify({ user_code: userCode }),
	});
	return deviceInspectSchema.parse(body);
}

export async function approveDeviceCode(
	userCode: string,
): Promise<{ approved: boolean; device_name: string; platform: string }> {
	const body = await apiFetch<unknown>("/auth/device/approve", {
		method: "POST",
		body: JSON.stringify({ user_code: userCode }),
	});
	return z
		.object({
			approved: z.boolean(),
			device_name: z.string(),
			platform: z.string(),
		})
		.parse(body);
}

const deviceSessionSchema = z.object({
	device_id: z.string(),
	device_name: z.string(),
	platform: z.string(),
	created_at: z.string(),
	last_used_at: z.string().nullable(),
	expires_at: z.string(),
});

export type DeviceSession = z.infer<typeof deviceSessionSchema>;

const deviceListSchema = z.object({
	items: z.array(deviceSessionSchema),
});

export async function fetchDevices(): Promise<DeviceSession[]> {
	const body = await apiFetch<unknown>("/auth/devices");
	return deviceListSchema.parse(body).items;
}

export async function revokeDevice(deviceId: string): Promise<void> {
	await apiFetch<unknown>(
		`/auth/devices/${encodeURIComponent(deviceId)}`,
		{ method: "DELETE" },
	);
}

export async function renameDevice(
	deviceId: string,
	name: string,
): Promise<void> {
	await apiFetch<unknown>(
		`/auth/devices/${encodeURIComponent(deviceId)}`,
		{
			method: "PATCH",
			body: JSON.stringify({ name }),
		},
	);
}
