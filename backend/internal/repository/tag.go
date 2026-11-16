package repository

import (
	"context"
	"errors"
	"strings"

	"flux/internal/models"

	"gorm.io/gorm"
)

var (
	ErrTagGroupInvalid   = errors.New("invalid tag group")
	ErrTagSlugRequired   = errors.New("tag slug is required")
	ErrTagNameRequired   = errors.New("tag name is required")
	ErrTagSlugTaken      = errors.New("tag slug already exists in this group")
	ErrTooManyFormatTags = errors.New("only one format tag is allowed")
	ErrFormatOnWork      = errors.New("format tags apply only to media")
	ErrTagsForImage      = errors.New("images cannot have tags")
	ErrTagNotFound       = errors.New("tag not found")
	ErrTagGroupImmutable = errors.New("tag group cannot be changed")
)

type TagStore struct {
	db *gorm.DB
}

func NewTagRepository(db *gorm.DB) *TagStore {
	return &TagStore{db: db}
}

func validTagGroup(group string) bool {
	return group == models.TagGroupFormat ||
		group == models.TagGroupGenre ||
		group == models.TagGroupMood
}

func normalizeTagSlug(slug string) string {
	return strings.ToLower(strings.TrimSpace(slug))
}

func (r *TagStore) List(ctx context.Context, group string) ([]models.Tag, error) {
	var rows []models.Tag
	query := r.db.WithContext(ctx)
	if group != "" {
		if !validTagGroup(group) {
			return nil, ErrTagGroupInvalid
		}
		query = query.Where("tag_group = ?", group)
	}
	err := query.Order("tag_group ASC, name ASC, id ASC").Find(&rows).Error
	return rows, err
}

func (r *TagStore) Create(ctx context.Context, tag *models.Tag) error {
	if !validTagGroup(tag.Group) {
		return ErrTagGroupInvalid
	}
	tag.Slug = normalizeTagSlug(tag.Slug)
	tag.Name = strings.TrimSpace(tag.Name)
	if tag.Slug == "" {
		return ErrTagSlugRequired
	}
	if tag.Name == "" {
		return ErrTagNameRequired
	}
	if err := r.db.WithContext(ctx).Create(tag).Error; err != nil {
		if isUniqueViolation(err) {
			return ErrTagSlugTaken
		}
		return err
	}
	return nil
}

func (r *TagStore) Update(ctx context.Context, id uint, group, slug, name string) (*models.Tag, error) {
	var tag models.Tag
	if err := r.db.WithContext(ctx).First(&tag, id).Error; err != nil {
		return nil, err
	}
	if group != "" && !validTagGroup(group) {
		return nil, ErrTagGroupInvalid
	}
	if group != "" && group != tag.Group {
		return nil, ErrTagGroupImmutable
	}
	updates := map[string]any{}
	if slug != "" {
		normalized := normalizeTagSlug(slug)
		if normalized == "" {
			return nil, ErrTagSlugRequired
		}
		updates["slug"] = normalized
	}
	if name != "" {
		normalized := strings.TrimSpace(name)
		if normalized == "" {
			return nil, ErrTagNameRequired
		}
		updates["name"] = normalized
	}
	if len(updates) > 0 {
		if err := r.db.WithContext(ctx).Model(&tag).Updates(updates).Error; err != nil {
			if isUniqueViolation(err) {
				return nil, ErrTagSlugTaken
			}
			return nil, err
		}
	}
	if err := r.db.WithContext(ctx).First(&tag, id).Error; err != nil {
		return nil, err
	}
	return &tag, nil
}

func (r *TagStore) Delete(ctx context.Context, id uint) error {
	res := r.db.WithContext(ctx).Delete(&models.Tag{}, id)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

func (r *TagStore) tagsByIDs(tx *gorm.DB, tagIDs []uint) ([]models.Tag, error) {
	if len(tagIDs) == 0 {
		return nil, nil
	}
	var tags []models.Tag
	if err := tx.Where("id IN ?", tagIDs).Find(&tags).Error; err != nil {
		return nil, err
	}
	if len(tags) != len(uniqueIDs(tagIDs)) {
		return nil, ErrTagNotFound
	}
	return tags, nil
}

func uniqueIDs(ids []uint) []uint {
	seen := make(map[uint]bool, len(ids))
	out := make([]uint, 0, len(ids))
	for _, id := range ids {
		if id == 0 || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func checkFormatExclusive(tags []models.Tag) error {
	count := 0
	for _, tag := range tags {
		if tag.Group == models.TagGroupFormat {
			count++
		}
	}
	if count > 1 {
		return ErrTooManyFormatTags
	}
	return nil
}

func (r *TagStore) SetMediaTags(ctx context.Context, mediaID uint, tagIDs []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var media models.Media
		if err := tx.First(&media, mediaID).Error; err != nil {
			return err
		}
		if media.Type == models.MediaTypeImage {
			return ErrTagsForImage
		}
		tags, err := r.tagsByIDs(tx, tagIDs)
		if err != nil {
			return err
		}
		if err := checkFormatExclusive(tags); err != nil {
			return err
		}
		if err := tx.Where("media_id = ?", mediaID).Delete(&models.MediaTag{}).Error; err != nil {
			return err
		}
		for _, id := range uniqueIDs(tagIDs) {
			if err := tx.Create(&models.MediaTag{MediaID: mediaID, TagID: id}).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *TagStore) SetWorkTags(ctx context.Context, workID uint, tagIDs []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var work models.Work
		if err := tx.First(&work, workID).Error; err != nil {
			return err
		}
		tags, err := r.tagsByIDs(tx, tagIDs)
		if err != nil {
			return err
		}
		for _, tag := range tags {
			if tag.Group == models.TagGroupFormat {
				return ErrFormatOnWork
			}
		}
		if err := tx.Where("work_id = ?", workID).Delete(&models.WorkTag{}).Error; err != nil {
			return err
		}
		for _, id := range uniqueIDs(tagIDs) {
			if err := tx.Create(&models.WorkTag{WorkID: workID, TagID: id}).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *TagStore) SetFranchiseTags(ctx context.Context, franchiseID uint, tagIDs []uint) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var franchise models.Franchise
		if err := tx.First(&franchise, franchiseID).Error; err != nil {
			return err
		}
		tags, err := r.tagsByIDs(tx, tagIDs)
		if err != nil {
			return err
		}
		for _, tag := range tags {
			if tag.Group == models.TagGroupFormat {
				return ErrFormatOnWork
			}
		}
		if err := tx.Where("franchise_id = ?", franchiseID).Delete(&models.FranchiseTag{}).Error; err != nil {
			return err
		}
		for _, id := range uniqueIDs(tagIDs) {
			if err := tx.Create(&models.FranchiseTag{FranchiseID: franchiseID, TagID: id}).Error; err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *TagStore) MediaTags(ctx context.Context, mediaID uint) ([]models.Tag, error) {
	var rows []models.Tag
	err := r.db.WithContext(ctx).
		Table("tags").
		Joins("JOIN media_tags ON media_tags.tag_id = tags.id").
		Where("media_tags.media_id = ?", mediaID).
		Order("tags.tag_group ASC, tags.name ASC").Find(&rows).Error
	return rows, err
}

func (r *TagStore) WorkTags(ctx context.Context, workID uint) ([]models.Tag, error) {
	var rows []models.Tag
	err := r.db.WithContext(ctx).
		Table("tags").
		Joins("JOIN work_tags ON work_tags.tag_id = tags.id").
		Where("work_tags.work_id = ?", workID).
		Order("tags.tag_group ASC, tags.name ASC").Find(&rows).Error
	return rows, err
}

func (r *TagStore) FranchiseTags(ctx context.Context, franchiseID uint) ([]models.Tag, error) {
	var rows []models.Tag
	err := r.db.WithContext(ctx).
		Table("tags").
		Joins("JOIN franchise_tags ON franchise_tags.tag_id = tags.id").
		Where("franchise_tags.franchise_id = ?", franchiseID).
		Order("tags.tag_group ASC, tags.name ASC").Find(&rows).Error
	return rows, err
}
