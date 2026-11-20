package handler

import (
	"context"
	"testing"
	"time"

	"github.com/JoelTeoGom/docvault/internal/domain"
)

type fakeSweepRepository struct {
	due         map[domain.Status][]*domain.File
	stored      map[string]domain.File
	conflicting map[string]bool
}

func (r *fakeSweepRepository) ListDue(_ context.Context, status domain.Status, _ time.Time) ([]*domain.File, error) {
	return r.due[status], nil
}

func (r *fakeSweepRepository) Transition(_ context.Context, file *domain.File, _ domain.Status) error {
	if r.conflicting[file.ID] {
		return domain.ErrInvalidStatus
	}
	r.stored[file.ID] = *file
	return nil
}

type fakeSweepStorage struct {
	objects map[string]bool
}

func (s *fakeSweepStorage) DeleteFile(_ context.Context, s3Key string) error {
	delete(s.objects, s3Key)
	return nil
}

func (s *fakeSweepStorage) ObjectExists(_ context.Context, s3Key string) (bool, error) {
	return s.objects[s3Key], nil
}

func TestSweeperRemovesObjects(t *testing.T) {
	trashed := &domain.File{ID: "trashed", S3Key: "users/u/trashed.pdf", Status: domain.StatusTrashed}
	deleted := &domain.File{ID: "deleted", S3Key: "users/u/deleted.pdf", Status: domain.StatusDeleted}
	rejected := &domain.File{ID: "rejected", S3Key: "users/u/rejected.pdf", Status: domain.StatusRejected}
	restored := &domain.File{ID: "restored", S3Key: "users/u/restored.pdf", Status: domain.StatusTrashed}

	repo := &fakeSweepRepository{
		due: map[domain.Status][]*domain.File{
			domain.StatusTrashed:  {trashed, restored},
			domain.StatusDeleted:  {deleted},
			domain.StatusRejected: {rejected},
		},
		stored:      map[string]domain.File{},
		conflicting: map[string]bool{"restored": true},
	}
	storage := &fakeSweepStorage{objects: map[string]bool{
		trashed.S3Key: true, deleted.S3Key: true, rejected.S3Key: true, restored.S3Key: true,
	}}

	if err := NewSweeper(repo, storage).HandleRequest(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	tests := []struct {
		id         string
		wantStatus domain.Status
	}{
		{id: "trashed", wantStatus: domain.StatusDeleted},
		{id: "deleted", wantStatus: domain.StatusDeleted},
		{id: "rejected", wantStatus: domain.StatusRejected},
	}
	for _, tc := range tests {
		stored := repo.stored[tc.id]
		if stored.Status != tc.wantStatus {
			t.Errorf("%s: status %s, want %s", tc.id, stored.Status, tc.wantStatus)
		}
		if !stored.S3Deleted {
			t.Errorf("%s: S3Deleted not set", tc.id)
		}
		if storage.objects["users/u/"+tc.id+".pdf"] {
			t.Errorf("%s: object still in the bucket", tc.id)
		}
	}

	if !storage.objects[restored.S3Key] {
		t.Error("restored: object of a file that left the trash was deleted")
	}
}
