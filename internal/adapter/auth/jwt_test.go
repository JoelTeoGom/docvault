package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testSecret = "test-secret"

func signToken(t *testing.T, method jwt.SigningMethod, claims jwt.MapClaims) string {
	t.Helper()

	token, err := jwt.NewWithClaims(method, claims).SignedString([]byte(testSecret))
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return token
}

func TestValidateToken(t *testing.T) {
	expiresAt := jwt.NewNumericDate(time.Now().Add(time.Minute))

	tests := []struct {
		name    string
		token   string
		wantErr bool
	}{
		{
			name:  "hs256 with expiration is accepted",
			token: signToken(t, jwt.SigningMethodHS256, jwt.MapClaims{"user_id": "user-1", "exp": expiresAt}),
		},
		{
			name:    "missing expiration is rejected",
			token:   signToken(t, jwt.SigningMethodHS256, jwt.MapClaims{"user_id": "user-1"}),
			wantErr: true,
		},
		{
			name:    "expired token is rejected",
			token:   signToken(t, jwt.SigningMethodHS256, jwt.MapClaims{"user_id": "user-1", "exp": jwt.NewNumericDate(time.Now().Add(-time.Minute))}),
			wantErr: true,
		},
		{
			name:    "other hmac algorithm is rejected",
			token:   signToken(t, jwt.SigningMethodHS512, jwt.MapClaims{"user_id": "user-1", "exp": expiresAt}),
			wantErr: true,
		},
	}

	service := NewJWTService(testSecret)

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			claims, err := service.ValidateToken(tc.token)

			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got claims %+v", claims)
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if claims.UserID != "user-1" {
				t.Errorf("user id: got %s, want user-1", claims.UserID)
			}
		})
	}
}
