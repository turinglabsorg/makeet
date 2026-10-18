package store

import (
	"database/sql"
	_ "modernc.org/sqlite"
	"os"
	"path/filepath"
)

func Open(path string) (*sql.DB, error) {
	if path != ":memory:" {
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			return nil, err
		}
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err = db.Exec(schema); err != nil {
		db.Close()
		return nil, err
	}
	if path != ":memory:" {
		if err = os.Chmod(path, 0600); err != nil {
			db.Close()
			return nil, err
		}
	}
	return db, nil
}

const schema = `
PRAGMA foreign_keys=ON;
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, email TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS profiles(user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL, image BLOB, revision INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS identities(provider TEXT NOT NULL, subject TEXT NOT NULL, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(provider,subject));
CREATE TABLE IF NOT EXISTS challenges(id TEXT PRIMARY KEY, provider TEXT NOT NULL, nonce TEXT NOT NULL, expires_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS challenges_expiry ON challenges(expires_at);
CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, refresh_hash TEXT NOT NULL UNIQUE, expires_at INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires_at);
CREATE TABLE IF NOT EXISTS access_tokens(hash TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, expires_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS access_expiry ON access_tokens(expires_at);
CREATE INDEX IF NOT EXISTS access_session ON access_tokens(session_id);
CREATE TABLE IF NOT EXISTS used_refresh(hash TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE);
CREATE INDEX IF NOT EXISTS used_refresh_session ON used_refresh(session_id);
CREATE INDEX IF NOT EXISTS identities_user ON identities(user_id);
CREATE TABLE IF NOT EXISTS records(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, deleted INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(user_id,kind,id));
CREATE TABLE IF NOT EXISTS changes(sequence INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL, deleted INTEGER NOT NULL, data TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS changes_user_sequence ON changes(user_id,sequence);
CREATE INDEX IF NOT EXISTS changes_record ON changes(user_id,kind,id);
CREATE TABLE IF NOT EXISTS batches(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, id TEXT NOT NULL, request_hash TEXT NOT NULL, response TEXT NOT NULL, PRIMARY KEY(user_id,id));
CREATE TABLE IF NOT EXISTS provider_grants(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, provider TEXT NOT NULL, audience TEXT NOT NULL, token BLOB NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(user_id,provider,audience));
CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, installation_hash TEXT NOT NULL, token BLOB NOT NULL, token_hash TEXT NOT NULL, topic TEXT NOT NULL, environment TEXT NOT NULL, language TEXT NOT NULL, time_zone TEXT NOT NULL, reminders_enabled INTEGER NOT NULL, reminder_hour INTEGER NOT NULL, reminder_minute INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(token_hash,topic,environment));
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);
CREATE INDEX IF NOT EXISTS devices_session ON devices(session_id);
CREATE INDEX IF NOT EXISTS devices_reminders ON devices(session_id) WHERE reminders_enabled=1;
CREATE TABLE IF NOT EXISTS push_messages(id TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL, day TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, accepted_at INTEGER NOT NULL DEFAULT 0, confirmed_at INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending');
CREATE INDEX IF NOT EXISTS push_due ON push_messages(status,next_attempt);
CREATE INDEX IF NOT EXISTS push_device ON push_messages(device_id,created_at);
CREATE INDEX IF NOT EXISTS push_expiry ON push_messages(created_at);
CREATE UNIQUE INDEX IF NOT EXISTS push_reminder_day ON push_messages(device_id,day) WHERE kind='reminder';
CREATE INDEX IF NOT EXISTS activity_day ON records(user_id,kind,deleted,json_extract(data,'$.habit_id'),unixepoch(json_extract(data,'$.timestamp')));
CREATE TABLE IF NOT EXISTS subscriptions(environment TEXT NOT NULL,original_id TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,transaction_id TEXT NOT NULL,product_id TEXT NOT NULL,expires_date INTEGER NOT NULL,signed_date INTEGER NOT NULL,revoked INTEGER NOT NULL,PRIMARY KEY(environment,original_id));
CREATE INDEX IF NOT EXISTS subscriptions_user_expiry ON subscriptions(user_id,revoked,expires_date DESC);
PRAGMA user_version=6;
`
