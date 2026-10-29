package services

import (
	"context"
	"fmt"
	"image"
	_ "image/jpeg" // превью мемов всегда JPEG
	"math/bits"
	"os"

	"github.com/corona10/goimagehash"

	"flux/internal/models"
	"flux/internal/repository"
)

// similarImageDistance — порог Хэмминга на 64-битном pHash. Пережатие
// обычно даёт 2–6 бит, 8 — запас, при котором разные мемы ещё не
// склеиваются.
const similarImageDistance = 8

// ImagePHash считает perceptual hash картинки. Вызывать нужно с превью,
// а не с оригиналом: декодирование 6000 px JPEG съело бы сотни мегабайт.
func ImagePHash(filePath string) (int64, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	img, _, err := image.Decode(file)
	if err != nil {
		return 0, fmt.Errorf("decode image: %w", err)
	}
	hash, err := goimagehash.PerceptionHash(img)
	if err != nil {
		return 0, fmt.Errorf("perceptual hash: %w", err)
	}
	return int64(hash.GetHash()), nil
}

// IsSimilarImage сравнивает два pHash по Хэммингу. Нулевой хэш означает
// «не посчитан» и ни с чем не совпадает.
func IsSimilarImage(a, b int64) bool {
	if a == 0 || b == 0 {
		return false
	}
	return bits.OnesCount64(uint64(a)^uint64(b)) <= similarImageDistance
}

// FindSimilarImage ищет ближайший по pHash неудалённый мем. Линейный
// проход: даже 10 тысяч XOR-popcount — доли миллисекунды.
func FindSimilarImage(
	ctx context.Context,
	mediaRepo repository.MediaRepository,
	phash int64,
	excludeID uint,
) (*models.Media, error) {
	if phash == 0 {
		return nil, nil
	}
	candidates, err := mediaRepo.FindImagesWithPHash(ctx, excludeID)
	if err != nil {
		return nil, err
	}
	for i := range candidates {
		if IsSimilarImage(phash, candidates[i].PHash) {
			return &candidates[i], nil
		}
	}
	return nil, nil
}
