const CODE = /^\d{6}$/;
const SEPARATORS = /[\s-]/g;
const NON_DIGIT = /\D/g;

// QR устройства содержит verification_uri_complete вида
// https://server/activate#code=123456. Принимаем только явный code
// из URL или голый шестизначный код: случайные цифры в пути — не код.
export function parseDeviceCodeFromQr(value: string): string | null {
	const raw = value.trim();
	if (raw === "") {
		return null;
	}
	const bare = raw.replace(SEPARATORS, "");
	if (CODE.test(bare)) {
		return bare;
	}
	let code: string | null = null;
	try {
		const url = new URL(raw);
		const hash = url.hash.startsWith("#") ? url.hash.slice(1) : url.hash;
		code =
			new URLSearchParams(hash).get("code") ?? url.searchParams.get("code");
	} catch {
		return null;
	}
	if (code === null) {
		return null;
	}
	const digits = code.replace(NON_DIGIT, "");
	return CODE.test(digits) ? digits : null;
}
