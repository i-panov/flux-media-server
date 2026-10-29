import { Music } from "lucide-react";
import { useState } from "react";

// Обложки может не быть, а файл на сервере — исчезнуть: <img> без onError
// оставляет в плеере иконку битой картинки. Контейнер задаёт размеры
// и скругление, компонент отвечает только за содержимое.
export function CoverImage({
	src,
	iconSize,
}: {
	src: string;
	iconSize: number;
}) {
	// Ошибка запоминается вместе с адресом: при смене трека (компонент
	// переиспользуется) сломанная обложка прошлого трека не должна
	// скрывать новую.
	const [failedSrc, setFailedSrc] = useState<string | null>(null);
	if (src === "" || failedSrc === src) {
		return (
			<Music size={iconSize} className="text-[var(--mantine-color-dimmed)]" />
		);
	}
	return (
		// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError — ошибка загрузки, а не интеракция.
		<img
			src={src}
			alt=""
			className="h-full w-full object-cover"
			onError={() => setFailedSrc(src)}
		/>
	);
}
