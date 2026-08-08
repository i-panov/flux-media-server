package repository

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInitDB(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)
	assert.NotNil(t, db)

	// Verify the connection is usable
	sqlDB, err := db.DB()
	require.NoError(t, err)
	assert.NoError(t, sqlDB.Ping())
}

func TestAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	require.NoError(t, err)

	err = AutoMigrate(db)
	assert.NoError(t, err)

	// Verify tables were created
	var tables []string
	err = db.Raw("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").Scan(&tables).Error
	assert.NoError(t, err)

	tableSet := make(map[string]bool)
	for _, t := range tables {
		tableSet[t] = true
	}

	assert.True(t, tableSet["media"])
	assert.True(t, tableSet["metadata"])
	assert.True(t, tableSet["users"])
	assert.True(t, tableSet["watch_progresses"])
	assert.True(t, tableSet["favorites"])
	assert.True(t, tableSet["collections"])
	assert.True(t, tableSet["collection_items"])
	assert.True(t, tableSet["lyrics"])
}
