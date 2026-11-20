package handler

import (
	"context"
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
}

func NewSweeper(repo SweepRepository, storage SweepStorage) *Sweeper {
	return &Sweeper{repo: repo, storage: storage}
}

func (s *Sweeper) HandleRequest(ctx context.Context) error {
	return nil
}
