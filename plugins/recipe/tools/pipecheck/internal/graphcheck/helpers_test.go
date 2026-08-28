package graphcheck

import (
	"testing"

	"github.com/courtesy/claude-plugins/recipe/pipecheck/internal/hash"
)

func skillHashes(t *testing.T, md string) (string, string) {
	t.Helper()
	c, b, err := hash.SkillHashes([]byte(md), nil)
	if err != nil {
		t.Fatal(err)
	}
	return c, b
}
