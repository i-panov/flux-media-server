package models

import "time"

// Collection is a user-created playlist of media items (e.g. "Want to Watch").
type Collection struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	UserID    uint      `gorm:"index" json:"user_id"`
	Name      string    `gorm:"size:255" json:"name"`
	Type      MediaType `gorm:"index;type:text" json:"type"` // video
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CollectionItem links a media item to a collection.
type CollectionItem struct {
	ID           uint `gorm:"primaryKey" json:"id"`
	CollectionID uint `gorm:"uniqueIndex:idx_collection_media;uniqueIndex:idx_collection_position" json:"collection_id"`
	MediaID      uint `gorm:"index;uniqueIndex:idx_collection_media" json:"media_id"`
	// ВНИМАНИЕ: idx_collection_position — UNIQUE по (collection_id, position).
	// Любой reorder позиций (сдвиг в середине списка) на мгновение создаёт
	// дубликат (collection_id, position) и падает на ограничении. Перестановка
	// требует пересоздания записей (удалить/вставить в новом порядке)
	// либо временного отключения ограничения. Position из AddItemAtomic
	// (MAX(position)+1) всегда безопасен.
	Position int       `gorm:"default:0;uniqueIndex:idx_collection_position" json:"position"`
	AddedAt  time.Time `json:"added_at"`
	// FK-ассоциации с каскадным удалением (для новых инсталляций).
	Collection *Collection `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
	Media      *Media      `gorm:"constraint:OnUpdate:CASCADE,OnDelete:CASCADE" json:"-"`
}
