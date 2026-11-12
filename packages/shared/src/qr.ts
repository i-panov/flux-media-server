import { toQR } from "toqr";

export interface QrMatrix {
	size: number;
	/** row-major, true — тёмный модуль. */
	cells: boolean[];
}

// toqr отдаёт квадратную матрицу байтами 0/1. Рендерят её клиенты:
// web — SVG, native — сеткой View, поэтому shared не тянет DOM/RN.
export function qrMatrix(value: string): QrMatrix {
	const bytes = toQR(value);
	const size = Math.sqrt(bytes.length);
	if (!Number.isInteger(size)) {
		throw new Error("QR matrix is not square");
	}
	return { size, cells: Array.from(bytes, (cell) => cell !== 0) };
}
