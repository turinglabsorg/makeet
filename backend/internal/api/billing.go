package api

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/turinglabsorg/makeet/backend/internal/billing"
)

type entitlement struct {
	Enabled   bool   `json:"billing_enabled"`
	Active    bool   `json:"active"`
	ProductID string `json:"product_id"`
	ExpiresAt int64  `json:"expires_at"`
}

func (s *Server) publicBillingEnabled() bool {
	return s.cfg.Billing != nil && len(s.cfg.BillingPreviewUsers) == 0
}
func (s *Server) billingEnabledFor(userID string) bool {
	return s.cfg.Billing != nil && (len(s.cfg.BillingPreviewUsers) == 0 || s.cfg.BillingPreviewUsers[userID])
}

func (s *Server) entitlement(ctx context.Context, userID string) (entitlement, error) {
	value := entitlement{Enabled: s.billingEnabledFor(userID)}
	if !value.Enabled {
		return value, nil
	}
	var expires int64
	err := s.db.QueryRowContext(ctx, `SELECT product_id,expires_date FROM subscriptions WHERE user_id=? AND revoked=0 AND expires_date>? AND (environment='Production' OR ?=1) ORDER BY expires_date DESC LIMIT 1`, userID, s.cfg.Clock().UnixMilli(), s.cfg.Billing.Sandbox).Scan(&value.ProductID, &expires)
	if errors.Is(err, sql.ErrNoRows) {
		return value, nil
	}
	if err != nil {
		return value, err
	}
	value.Active = true
	value.ExpiresAt = expires / 1000
	return value, nil
}
func (s *Server) getEntitlement(w http.ResponseWriter, r *http.Request, p principal) {
	value, err := s.entitlement(r.Context(), p.UserID)
	if err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, value)
}
func (s *Server) submitTransaction(w http.ResponseWriter, r *http.Request, p principal) {
	if s.cfg.Billing == nil {
		fail(w, 503, "billing_unavailable")
		return
	}
	var req struct {
		Signed string `json:"signed_transaction"`
	}
	if !decode(w, r, &req) {
		return
	}
	value, err := s.cfg.Billing.TransactionContext(r.Context(), req.Signed, s.cfg.Clock())
	if errors.Is(err, billing.ErrUnavailable) {
		fail(w, 503, "billing_verification_unavailable")
		return
	}
	if err != nil {
		fail(w, 400, "invalid_transaction")
		return
	}
	if value.Environment == "Sandbox" && len(s.cfg.BillingPreviewUsers) > 0 && !s.cfg.BillingPreviewUsers[p.UserID] {
		fail(w, 403, "sandbox_account_not_enabled")
		return
	}
	if value.AccountToken != p.UserID {
		fail(w, 403, "transaction_account_mismatch")
		return
	}
	if err = s.storeTransaction(r.Context(), value, false); err != nil {
		if errors.Is(err, errPurchaseOwner) {
			fail(w, 403, "transaction_account_mismatch")
		} else {
			internal(w, err)
		}
		return
	}
	s.getEntitlement(w, r, p)
}

var errPurchaseOwner = errors.New("subscription belongs to another account")

func (s *Server) storeTransaction(ctx context.Context, value billing.Transaction, revoke bool) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var owner string
	err = tx.QueryRowContext(ctx, "SELECT user_id FROM subscriptions WHERE environment=? AND original_id=?", value.Environment, value.OriginalID).Scan(&owner)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if owner != "" && owner != value.AccountToken {
		return errPurchaseOwner
	}
	// Unknown/deleted accounts cannot be recreated by a delayed notification.
	var exists int
	if err = tx.QueryRowContext(ctx, "SELECT count(*) FROM users WHERE id=?", value.AccountToken).Scan(&exists); err != nil {
		return err
	}
	if exists == 0 {
		return nil
	}
	revoked := value.RevocationDate > 0 || revoke
	_, err = tx.ExecContext(ctx, `INSERT INTO subscriptions(environment,original_id,user_id,transaction_id,product_id,expires_date,signed_date,revoked) VALUES(?,?,?,?,?,?,?,?)
 ON CONFLICT(environment,original_id) DO UPDATE SET transaction_id=excluded.transaction_id,product_id=excluded.product_id,expires_date=excluded.expires_date,signed_date=excluded.signed_date,revoked=excluded.revoked
 WHERE excluded.signed_date>subscriptions.signed_date OR (excluded.signed_date=subscriptions.signed_date AND excluded.revoked=1)`, value.Environment, value.OriginalID, value.AccountToken, value.ID, value.ProductID, value.ExpiresDate, value.SignedDate, revoked)
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Server) appStoreNotification(w http.ResponseWriter, r *http.Request) {
	if s.cfg.Billing == nil {
		fail(w, 503, "billing_unavailable")
		return
	}
	var req struct {
		Signed string `json:"signedPayload"`
	}
	if !decode(w, r, &req) {
		return
	}
	value, err := s.cfg.Billing.NotificationContext(r.Context(), req.Signed, s.cfg.Clock())
	if errors.Is(err, billing.ErrUnavailable) {
		fail(w, 503, "billing_verification_unavailable")
		return
	}
	if err != nil {
		fail(w, 400, "invalid_notification")
		return
	}
	if value.Data.Transaction == "" {
		if value.Type == "TEST" {
			w.WriteHeader(204)
			return
		}
		fail(w, 400, "transaction_required")
		return
	}
	purchase, err := s.cfg.Billing.TransactionContext(r.Context(), value.Data.Transaction, s.cfg.Clock())
	if errors.Is(err, billing.ErrUnavailable) {
		fail(w, 503, "billing_verification_unavailable")
		return
	}
	if err != nil || purchase.Environment != value.Data.Environment {
		fail(w, 400, "invalid_transaction")
		return
	}
	if purchase.Environment == "Sandbox" && len(s.cfg.BillingPreviewUsers) > 0 && !s.cfg.BillingPreviewUsers[purchase.AccountToken] {
		w.WriteHeader(204)
		return
	}
	// The signed outer event date orders refunds/renewals even when its nested transaction is older.
	if value.SignedDate > purchase.SignedDate {
		purchase.SignedDate = value.SignedDate
	}
	revoke := value.Type == "REFUND" || value.Type == "REVOKE"
	if value.Type == "EXPIRED" || value.Type == "GRACE_PERIOD_EXPIRED" {
		purchase.ExpiresDate = min(purchase.ExpiresDate, value.SignedDate)
	}
	if err = s.storeTransaction(r.Context(), purchase, revoke); err != nil {
		internal(w, err)
		return
	}
	w.WriteHeader(204)
}
func (s *Server) exportAccount(w http.ResponseWriter, r *http.Request, p principal) {
	rows, err := s.db.QueryContext(r.Context(), "SELECT kind,id,revision,deleted,data FROM records WHERE user_id=? AND deleted=0 ORDER BY kind,id", p.UserID)
	if err != nil {
		internal(w, err)
		return
	}
	defer rows.Close()
	records := []Record{}
	for rows.Next() {
		var value Record
		var raw string
		if err = rows.Scan(&value.Kind, &value.ID, &value.Revision, &value.Deleted, &raw); err != nil {
			internal(w, err)
			return
		}
		value.Data = json.RawMessage(raw)
		records = append(records, value)
	}
	if err = rows.Err(); err != nil {
		internal(w, err)
		return
	}
	respond(w, 200, struct {
		Version int       `json:"version"`
		Date    time.Time `json:"exported_at"`
		Records []Record  `json:"records"`
	}{1, s.cfg.Clock(), records})
}
