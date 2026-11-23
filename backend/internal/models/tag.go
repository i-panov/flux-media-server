package models

import "time"

const (
	TagGroupFormat = "format"
	TagGroupGenre  = "genre"
)

// Tag — глобальная смысловая метка: формат или жанр. Набор групп
// фиксирован в коде и проверяется при создании.
type Tag struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Group     string    `gorm:"column:tag_group;not null;uniqueIndex:idx_tags_group_slug,priority:1;index" json:"group"`
	Slug      string    `gorm:"not null;uniqueIndex:idx_tags_group_slug,priority:2" json:"slug"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type MediaTag struct {
	MediaID uint  `gorm:"primaryKey" json:"media_id"`
	TagID   uint  `gorm:"primaryKey;index" json:"tag_id"`
	Media   Media `gorm:"foreignKey:MediaID;constraint:OnDelete:CASCADE" json:"-"`
	Tag     Tag   `gorm:"foreignKey:TagID;constraint:OnDelete:CASCADE" json:"-"`
}

type WorkTag struct {
	WorkID uint `gorm:"primaryKey" json:"work_id"`
	TagID  uint `gorm:"primaryKey;index" json:"tag_id"`
	Work   Work `gorm:"foreignKey:WorkID;constraint:OnDelete:CASCADE" json:"-"`
	Tag    Tag  `gorm:"foreignKey:TagID;constraint:OnDelete:CASCADE" json:"-"`
}

type FranchiseTag struct {
	FranchiseID uint      `gorm:"primaryKey" json:"franchise_id"`
	TagID       uint      `gorm:"primaryKey;index" json:"tag_id"`
	Franchise   Franchise `gorm:"foreignKey:FranchiseID;constraint:OnDelete:CASCADE" json:"-"`
	Tag         Tag       `gorm:"foreignKey:TagID;constraint:OnDelete:CASCADE" json:"-"`
}
