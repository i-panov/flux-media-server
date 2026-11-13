package services

import "testing"

func TestPublishingPathReservation(t *testing.T) {
	path := "/library/video/new.mp4"
	if IsPublishingPath(path) {
		t.Fatal("path must not be reserved initially")
	}
	release := ReservePublishingPath(path)
	if !IsPublishingPath(path) {
		t.Fatal("path must be reserved")
	}
	release()
	if IsPublishingPath(path) {
		t.Fatal("release must clear reservation")
	}
	// Идемпотентность: повторный вызов не паникует и не трогает чужой резерв.
	release()
	other := ReservePublishingPath("/library/video/other.mp4")
	defer other()
	if IsPublishingPath(path) || !IsPublishingPath("/library/video/other.mp4") {
		t.Fatal("reservations must be independent")
	}
}
