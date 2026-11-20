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
	failed := 0

	for _, status := range []domain.Status{domain.StatusTrashed, domain.StatusDeleted, domain.StatusRejected} {
		files, err := s.repo.ListDue(ctx, status, s.now())
		if err != nil {
			return err
		}

		for _, file := range files {
			err := s.removeObject(ctx, file)
			if errors.Is(err, domain.ErrInvalidStatus) || errors.Is(err, domain.ErrFileNotFound) {
				slog.InfoContext(ctx, "file changed during the sweep, skipped", "file", file.ID)
				continue
			}
			if err != nil {
				failed++
				slog.ErrorContext(ctx, "sweep failed", "file", file.ID, "status", file.Status, "error", err)
			}
		}
	}

	if failed > 0 {
		return fmt.Errorf("sweep failed for %d files", failed)
	}
	return nil
}

// removeObject deletes the bytes of a file the user can no longer reach. A
// trashed file past its retention is first deleted for good, so the API stops
// serving it before its bytes disappear.
func (s *Sweeper) removeObject(ctx context.Context, file *domain.File) error {
	if file.IsTrashed() {
		file.Status = domain.StatusDeleted
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
