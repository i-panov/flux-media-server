package repository

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestInitDB(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)
	assert.NotNil(t, db)
}

func TestAutoMigrate(t *testing.T) {
	db, err := InitDB(":memory:")
	assert.NoError(t, err)

	err = AutoMigrate(db)
	assert.NoError(t, err)
}
