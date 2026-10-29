package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	_ "modernc.org/sqlite"
)

const (
	maxUsernameRunes      = 32
	maxPasswordRunes      = 64
	maxRegisteredStudents = 60
	maxStudentNameRunes   = 32
)

var (
	errUsernameTaken    = errors.New("该用户名已被注册")
	errUsernameReserved = errors.New("该用户名已被保留")
	errTooManyStudents  = errors.New("学生名单最多 60 人")
	errStudentNameLong  = errors.New("学生姓名过长（每个姓名最多 32 个字符）")
)

// AccountRegistry stores the classroom accounts registered through the API
// in a SQLite database, so they survive backend restarts.
type AccountRegistry struct {
	db *sql.DB
}

// newAccountRegistry opens the SQLite database at path (or ":memory:") and
// creates the accounts table if it does not exist yet.
func newAccountRegistry(path string) (*AccountRegistry, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite database %q: %w", path, err)
	}
	if _, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS accounts (
			username TEXT PRIMARY KEY NOT NULL,
			password TEXT NOT NULL,
			students TEXT NOT NULL
		)
	`); err != nil {
		db.Close()
		return nil, fmt.Errorf("create accounts table: %w", err)
	}
	return &AccountRegistry{db: db}, nil
}

// Register stores username with its password and student roster.
func (r *AccountRegistry) Register(username, password string, students []string) error {
	if username == sharedAccount {
		return errUsernameReserved
	}
	if len(students) > maxRegisteredStudents {
		return errTooManyStudents
	}
	for _, name := range students {
		if utf8.RuneCountInString(name) > maxStudentNameRunes {
			return errStudentNameLong
		}
	}

	var exists int
	err := r.db.QueryRow(`SELECT 1 FROM accounts WHERE username = ?`, username).Scan(&exists)
	switch {
	case err == nil:
		return errUsernameTaken
	case !errors.Is(err, sql.ErrNoRows):
		return err
	}

	roster, err := json.Marshal(students)
	if err != nil {
		return fmt.Errorf("encode student roster: %w", err)
	}
	if _, err := r.db.Exec(
		`INSERT INTO accounts (username, password, students) VALUES (?, ?, ?)`,
		username, password, string(roster),
	); err != nil {
		return err
	}
	return nil
}

// Verify reports whether username matches password and returns the roster
// stored at registration time.
func (r *AccountRegistry) Verify(username, password string) ([]string, bool) {
	var storedPassword, roster string
	err := r.db.QueryRow(
		`SELECT password, students FROM accounts WHERE username = ?`,
		username,
	).Scan(&storedPassword, &roster)
	if err != nil || storedPassword != password {
		return nil, false
	}

	var students []string
	if err := json.Unmarshal([]byte(roster), &students); err != nil {
		return nil, false
	}
	return students, true
}

// parseStudentRoster splits a raw roster into one name per line, trimming
// surrounding whitespace and skipping empty lines.
func parseStudentRoster(raw string) []string {
	lines := strings.FieldsFunc(raw, func(r rune) bool {
		return r == '\n' || r == '\r'
	})
	names := make([]string, 0, len(lines))
	for _, line := range lines {
		if name := strings.TrimSpace(line); name != "" {
			names = append(names, name)
		}
	}
	return names
}
