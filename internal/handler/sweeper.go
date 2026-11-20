package handler

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/JoelTeoGom/docvault/internal/domain"
)

type SweepRepository interface {
	ListDue(ctx context.Context, status domain.Status, dueBefore time.Time) ([]*domain.File, error)
	Transition(ctx context.Context, file *domain.File, from domain.Status) error
	Delete(ctx context.Context, file *domain.File, from domain.Status) error
}

type SweepStorage interface {
	DeleteFile(ctx context.Context, s3Key string) error
	ObjectExists(ctx context.Context, s3Key string) (bool, error)
}

type Sweeper struct {
	repo    SweepRepository
	storage SweepStorage
	now     func() time.Time
}

func NewSweeper(repo SweepRepository, storage SweepStorage) *Sweeper {
	return &Sweeper{repo: repo, storage: storage, now: time.Now}
}

func (s *Sweeper) HandleRequest(ctx context.Context) error {
	sweeps := []struct {
		status    domain.Status
		dueBefore time.Time
		sweep     func(context.Context, *domain.File) error
	}{
		{status: domain.StatusTrashed, dueBefore: s.now(), sweep: s.removeObject},
		{status: domain.StatusDeleted, dueBefore: s.now(), sweep: s.removeObject},
		{status: domain.StatusRejected, dueBefore: s.now(), sweep: s.removeObject},
		{status: domain.StatusPending, dueBefore: s.now().Add(-domain.PendingUploadGrace), sweep: s.settlePending},
	}

	failed := 0
	for _, current := range sweeps {
		files, err := s.repo.ListDue(ctx, current.status, current.dueBefore)
		if err != nil {
			return err
		}

		for _, file := range files {
			err := current.sweep(ctx, file)
			if errors.Is(err, domain.ErrInvalidStatus) || errors.Is(err, domain.ErrFileNotFound) {
				slog.InfoContext(ctx, "file changed during the sweep, skipped", "file", file.ID)
				continue
			}
			if err != nil {
				failed++
				slog.ErrorContext(ctx, "sweep failed", "file", file.ID, "status", current.status, "error", err)
			}
		}
	}

	if failed > 0 {
		return fmt.Errorf("sweep failed for %d files", failed)
	}
	return nil
}

// settlePending resolves an upload that never got its S3 event. The object is
// the proof: if it exists the upload worked and the event was lost, and its size
// already matches the record because Content-Length is part of the signature.
func (s *Sweeper) settlePending(ctx context.Context, file *domain.File) error {
	exists, err := s.storage.ObjectExists(ctx, file.S3Key)
	if err != nil {
		return err
	}

	if exists {
		file.Status = domain.StatusUploaded
		return s.repo.Transition(ctx, file, domain.StatusPending)
	}
	return s.repo.Delete(ctx, file, domain.StatusPending)
}

// removeObject deletes the bytes of a file the user can no longer reach. A
// trashed file past its retention is first deleted for good, so the API stops
// serving it before its bytes disappear.
func (s *Sweeper) removeObject(ctx context.Context, file *domain.File) error {
	if file.IsTrashed() {
		file.Close(domain.StatusDeleted, s.now())
		if err := s.repo.Transition(ctx, file, domain.StatusTrashed); err != nil {
			return err
		}
	}

	if err := s.storage.DeleteFile(ctx, file.S3Key); err != nil {
		return err
	}

	file.S3Deleted = true
	return s.repo.Transition(ctx, file, file.Status)
}
