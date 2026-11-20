package handler

import (
	"context"
	"time"

	"github.com/JoelTeoGom/docvault/internal/domain"
)

type API struct {
	repo FileRepository
	s3   S3service
}

func NewAPI(repo FileRepository, s3 S3service) *API {
	return &API{
		repo: repo,
		s3:   s3,
	}
}

type FileRepository interface {
	Get(ctx context.Context, userID, fileID string) (*domain.File, error)
	Save(ctx context.Context, f *domain.File) error
	List(ctx context.Context, userID, cursor string, limit int) ([]*domain.File, string, error)
	Transition(ctx context.Context, file *domain.File, from domain.Status) error
}
type TokenValidator interface {
	ValidateToken(token string) (*domain.Claims, error)
}

type S3service interface {
	DeleteFile(ctx context.Context, s3Key string) error
	PresignDownload(ctx context.Context, s3Key string) (string, error)
	PresignUpload(ctx context.Context, s3Key, contentType string, contentLength int64) (string, error)
}

// Get returns the stored file along with a presigned URL to download it.
func (api *API) Get(ctx context.Context, userID, fileID string) (*domain.File, string, error) {
	if fileID == "" {
		return nil, "", domain.ErrFileNotFound
	}
	if userID == "" {
		return nil, "", domain.ErrUnauthorized
	}

	file, err := api.repo.Get(ctx, userID, fileID)
	if err != nil {
		return nil, "", err
	}
	if file == nil {
		return nil, "", domain.ErrFileNotFound
	}
	if file.IsTrashed() {
		return nil, "", domain.ErrFileTrashed
	}
	if !file.CanBeDownloaded() {
		return nil, "", domain.ErrNotReady
	}
	presignedURL, err := api.s3.PresignDownload(ctx, file.S3Key)
	if err != nil {
		return nil, "", err
	}

	return file, presignedURL, nil
}

func (api *API) Restore(ctx context.Context, userID, fileID string) (*domain.File, string, error) {
	if fileID == "" {
		return nil, "", domain.ErrFileNotFound
	}
	if userID == "" {
		return nil, "", domain.ErrUnauthorized
	}

	file, err := api.repo.Get(ctx, userID, fileID)
	if err != nil {
		return nil, "", err
	}
	if file == nil {
		return nil, "", domain.ErrFileNotFound
	}
	if !file.CanBeRestored() {
		return nil, "", domain.ErrInvalidStatus
	}

	file.Status = domain.StatusUploaded
	file.TrashedAt = time.Time{}
	file.TrashExpiresAt = time.Time{}
	if err := api.repo.Transition(ctx, file, domain.StatusTrashed); err != nil {
		return nil, "", err
	}

	presignedURL, err := api.s3.PresignDownload(ctx, file.S3Key)
	if err != nil {
		return nil, "", err
	}

	return file, presignedURL, nil
}

// Save records the pending file and returns it along with a presigned URL the
// client uses to upload the bytes directly to S3.
func (api *API) Save(ctx context.Context, userId, filename string, size int64, mime string) (*domain.File, string, error) {
	if userId == "" {
		return nil, "", domain.ErrUnauthorized
	}
	if filename == "" || size <= 0 || mime == "" {
		return nil, "", domain.ErrInvalidInput
	}

	if size > domain.MaxFileSize {
		return nil, "", domain.ErrFileTooLarge
	}

	if mime != domain.MimeTypePDF {
		return nil, "", domain.ErrInvalidMimeType
	}
	fileID := domain.NewFileID()
	file := &domain.File{
		ID:        fileID,
		OwnerID:   userId,
		S3Key:     domain.S3KeyFor(userId, fileID),
		Filename:  filename,
		Size:      size,
		Mime:      mime,
		Status:    domain.StatusPending,
		CreatedAt: time.Now(),
	}
	if err := api.repo.Save(ctx, file); err != nil {
		return nil, "", err
	}
	presignedURL, err := api.s3.PresignUpload(ctx, file.S3Key, file.Mime, file.Size)
	if err != nil {
		return nil, "", err
	}
	return file, presignedURL, nil
}

func (api *API) List(ctx context.Context, userID, cursor string, limit int) ([]*domain.File, string, error) {
	if userID == "" {
		return nil, "", domain.ErrUnauthorized
	}

	return api.repo.List(ctx, userID, cursor, limit)
}

func (api *API) MarkDeleted(ctx context.Context, userID, fileID string) error {
	if userID == "" {
		return domain.ErrUnauthorized
	}
	if fileID == "" {
		return domain.ErrFileNotFound
	}

	file, err := api.repo.Get(ctx, userID, fileID)
	if err != nil {
		return err
	}
	if file == nil {
		return domain.ErrFileNotFound
	}

	switch {
	case file.CanBeTrashed():
		file.Status = domain.StatusTrashed
		file.TrashedAt = time.Now()
		file.TrashExpiresAt = file.TrashedAt.Add(domain.DefaultTrashRetention)
		return api.repo.Transition(ctx, file, domain.StatusUploaded)

	case file.IsTrashed():
		file.Status = domain.StatusDeleted
		if err := api.repo.Transition(ctx, file, domain.StatusTrashed); err != nil {
			return err
		}
		// Dynamo is updated first so the API stops serving the file straight away.
		// A failure here only leaks the bytes, which the reconciliation job sweeps.
		if err := api.s3.DeleteFile(ctx, file.S3Key); err != nil {
			return err
		}
		file.S3Deleted = true
		return api.repo.Transition(ctx, file, domain.StatusDeleted)

	default:
		return domain.ErrInvalidStatus
	}
}
