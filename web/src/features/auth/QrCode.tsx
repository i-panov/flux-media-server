import { qrMatrix } from "@flux/shared";

interface QrCodeProps {
	value: string;
	size?: number;
	label: string;
}

// Рисуем матрицу в SVG без canvas/внешних сервисов: QR не уходит на
// сторонний генератор и работает офлайн.
export function QrCode({ value, size = 220, label }: QrCodeProps) {
	const matrix = qrMatrix(value);
	const cell = size / matrix.size;
	return (
		<svg
			width={size}
			height={size}
			viewBox={`0 0 ${size} ${size}`}
			role="img"
			aria-label={label}
			data-testid="device-qr"
			style={{ background: "#fff", borderRadius: 8 }}
		>
			<rect width={size} height={size} fill="#fff" />
			{matrix.cells.map((dark, index) =>
				dark ? (
					<rect
						// Матрица фиксированного размера, индекс стабилен.
						// biome-ignore lint/suspicious/noArrayIndexKey: матрица QR неизменяемая.
						key={index}
						x={(index % matrix.size) * cell}
						y={Math.floor(index / matrix.size) * cell}
						width={cell + 0.2}
						height={cell + 0.2}
						fill="#000"
					/>
				) : null,
			)}
		</svg>
	);
}
