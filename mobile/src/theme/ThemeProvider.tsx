import AsyncStorage from "@react-native-async-storage/async-storage";
import { StatusBar } from "expo-status-bar";
import * as SystemUI from "expo-system-ui";
import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { Appearance, useColorScheme } from "react-native";
import {
	getThemeTokens,
	parseThemeMode,
	resolveTheme,
	THEME_STORAGE_KEY,
	type ThemeMode,
	type ThemeTokens,
} from "./tokens";

interface ThemeContextValue extends ThemeTokens {
	readonly mode: ThemeMode;
	readonly setMode: (mode: ThemeMode) => void;
	/** AsyncStorage-настройка прочитана; до этого splash держится в _layout. */
	readonly hydrated: boolean;
	/** Последний режим, успешно записанный в AsyncStorage (null — ещё нет). */
	readonly persistedMode: ThemeMode | null;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
	// Системная схема обновляется автоматически при смене настроек ОС.
	const systemScheme = useColorScheme();
	const [mode, setModeState] = useState<ThemeMode>("system");
	const [hydrated, setHydrated] = useState(false);
	const [persistedMode, setPersistedMode] = useState<ThemeMode | null>(null);
	// Пользователь успел переключить тему раньше, чем AsyncStorage ответил:
	// поздний ответ не должен перетереть его выбор.
	const changedByUser = useRef(false);
	// Номер последней записи: ответы setItem приходят по порядку, но
	// persistedMode должен отражать именно последний выбор.
	const persistRequest = useRef(0);
	const tokens = useMemo(
		() => getThemeTokens(resolveTheme(mode, systemScheme)),
		[mode, systemScheme],
	);

	useEffect(() => {
		let active = true;
		AsyncStorage.getItem(THEME_STORAGE_KEY)
			.then((stored) => {
				if (active && !changedByUser.current) {
					const storedMode = parseThemeMode(stored);
					setModeState(storedMode);
					if (stored !== null) {
						setPersistedMode(storedMode);
					}
				}
			})
			.catch((error: unknown) => {
				console.warn("flux-theme: не удалось прочитать тему", error);
			})
			.finally(() => {
				if (active) {
					setHydrated(true);
				}
			});
		return () => {
			active = false;
		};
	}, []);

	const setMode = useCallback((next: ThemeMode) => {
		changedByUser.current = true;
		setModeState(next);
		const request = ++persistRequest.current;
		AsyncStorage.setItem(THEME_STORAGE_KEY, next)
			.then(() => {
				if (persistRequest.current === request) {
					setPersistedMode(next);
				}
			})
			.catch((error: unknown) => {
				console.warn("flux-theme: не удалось сохранить тему", error);
			});
	}, []);

	// Корневой фон нативной вьюхи: без него при смене темы остаются светлые
	// полосы за пределами SafeArea.
	useEffect(() => {
		SystemUI.setBackgroundColorAsync(tokens.colors.background).catch(() => {
			// На web/в отдельных окружениях фон корневой вьюхи недоступен.
		});
	}, [tokens.colors.background]);

	// Нативные контролы (Button, Switch, Alert) следуют выбранной схеме,
	// а не только наши токены. "auto" возвращает системный режим.
	useEffect(() => {
		Appearance.setColorScheme(mode === "system" ? "auto" : mode);
	}, [mode]);

	const value = useMemo<ThemeContextValue>(
		() => ({ ...tokens, mode, setMode, hydrated, persistedMode }),
		[tokens, mode, setMode, hydrated, persistedMode],
	);

	return (
		<ThemeContext.Provider value={value}>
			<StatusBar style={tokens.scheme === "dark" ? "light" : "dark"} />
			{children}
		</ThemeContext.Provider>
	);
}

export function useTheme(): ThemeContextValue {
	const value = useContext(ThemeContext);
	if (value === null) {
		throw new Error("useTheme должен использоваться внутри ThemeProvider");
	}
	return value;
}
