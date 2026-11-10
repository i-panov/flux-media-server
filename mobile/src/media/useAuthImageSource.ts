import { useEffect, useState } from "react";
import { type AuthSource, imageSource } from "./source";

// Bearer-заголовки читаются из SecureStore асинхронно, поэтому картинка
// получает source после загрузки. Path привязан к source: при смене
// медиа старая картинка не показывается, пока грузится новая.
export function useAuthImageSource(path: string | null): AuthSource | null {
	const [loaded, setLoaded] = useState<{
		path: string;
		source: AuthSource;
	} | null>(null);

	useEffect(() => {
		if (path === null) {
			return;
		}
		let active = true;
		imageSource(path).then(
			(next) => {
				if (active) {
					setLoaded({ path, source: next });
				}
			},
			() => {
				if (active) {
					setLoaded(null);
				}
			},
		);
		return () => {
			active = false;
		};
	}, [path]);

	return loaded !== null && loaded.path === path ? loaded.source : null;
}
