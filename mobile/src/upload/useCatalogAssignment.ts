import type { Media } from "@flux/shared";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	useAddEpisode,
	useAddFilm,
	useAddFranchiseEntry,
} from "../api/catalog";
import type { UploadDestinationValue } from "../components/UploadDestination";
import { t } from "../i18n";
import { assignmentFor } from "./destination";

// После успешной загрузки добавляет видео в выбранное место каталога.
// Ошибка назначения не отменяет загрузку: файл уже в библиотеке, поэтому
// показываем отдельное сообщение.
export function useCatalogAssignment(destination: UploadDestinationValue) {
	const [error, setError] = useState<string | null>(null);
	const addEpisode = useAddEpisode();
	const addFilm = useAddFilm();
	const addFranchiseEntry = useAddFranchiseEntry();
	const destinationRef = useRef(destination);
	useEffect(() => {
		destinationRef.current = destination;
	}, [destination]);

	const assign = useCallback(
		(media: Media | null) => {
			const assignment = assignmentFor(destinationRef.current, media);
			if (assignment === null) return;
			setError(null);
			const onError = () => setError(t("upload.destination.addError"));
			if (assignment.kind === "episode") {
				addEpisode.mutate(
					{ seasonID: assignment.seasonID, mediaID: assignment.mediaID },
					{ onError },
				);
				return;
			}
			if (assignment.kind === "film") {
				addFilm.mutate(
					{ workID: assignment.workID, mediaID: assignment.mediaID },
					{ onError },
				);
				return;
			}
			addFranchiseEntry.mutate(
				{ franchiseID: assignment.franchiseID, mediaID: assignment.mediaID },
				{ onError },
			);
		},
		[addEpisode, addFilm, addFranchiseEntry],
	);

	return { error, assign, clearError: () => setError(null) };
}
