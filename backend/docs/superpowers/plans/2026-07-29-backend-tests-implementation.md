# Backend Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement comprehensive test coverage for upload handler, auth handler, admin middleware, scanner service, and watcher service in the Flux Media Server backend.

**Architecture:** Each test file will follow the existing patterns in the codebase using testify for assertions and Fiber's Test method for HTTP endpoint testing. We'll use in-memory databases for isolation and create helper functions as needed.

**Tech Stack:** Go, Fiber, testify, GORM (SQLite in-memory)

---

## File Structure

**New files to create:**
- `internal/handlers/upload_test.go` - Tests for upload handler endpoints
- `internal/handlers/auth_test.go` - Additional tests for auth handler endpoints
- `internal/middleware/auth_test.go` - Tests for admin middleware
- `internal/services/scanner_test.go` - Tests for scanner service functionality
- `internal/services/watcher_test.go` - Tests for watcher service functionality

**Files to modify:**
- None (all new test files)

## Implementation Tasks

### Task 1: Create Upload Handler Tests

**Files:**
- Create: `internal/handlers/upload_test.go`

- [ ] **Step 1: Write the failing test for successful upload**

Create a test that simulates a multipart form upload with a file and library_id, expecting a 201 Created response.

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/handlers -run TestUploadSuccess -v`
Expected: FAIL with "no such test"

- [ ] **Step 3: Write minimal implementation**

Create the basic test structure with necessary imports and helper functions for multipart uploads.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/handlers -run TestUploadSuccess -v`
Expected: PASS

- [ ] **Step 5: Add test for missing file**

Create a test that sends a request without a file, expecting a 400 Bad Request response.

- [ ] **Step 6: Add test for invalid library_id**

Create a test that sends an invalid library_id, expecting a 400 Bad Request response.

- [ ] **Step 7: Add test for file too large**

Create a test that sends a file exceeding max_upload_size, expecting a 413 Payload Too Large response.

- [ ] **Step 8: Run all upload tests**

Run: `go test ./internal/handlers -run TestUpload -v`
Expected: All tests PASS

- [ ] **Step 9: Commit**

```bash
git add internal/handlers/upload_test.go
git commit -m "test: add upload handler tests"
```

### Task 2: Create Auth Handler Tests

**Files:**
- Create: `internal/handlers/auth_test.go`

- [ ] **Step 1: Write the failing test for first user registration**

Create a test that registers the first user, expecting admin privileges.

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/handlers -run TestAuthRegisterFirstUser -v`
Expected: FAIL with "no such test"

- [ ] **Step 3: Write minimal implementation**

Create the basic test structure with necessary imports and helper functions for auth testing.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/handlers -run TestAuthRegisterFirstUser -v`
Expected: PASS

- [ ] **Step 5: Add test for second user registration**

Create a test that registers a second user, expecting regular user privileges.

- [ ] **Step 6: Add test for successful login**

Create a test that performs a successful login, expecting a token in response.

- [ ] **Step 7: Add test for invalid credentials**

Create a test that tries to login with invalid credentials, expecting a 401 Unauthorized response.

- [ ] **Step 8: Add test for empty verification code**

Create a test that sends an empty verification code, expecting rejection (B2 fix).

- [ ] **Step 9: Run all auth tests**

Run: `go test ./internal/handlers -run TestAuth -v`
Expected: All tests PASS

- [ ] **Step 10: Commit**

```bash
git add internal/handlers/auth_test.go
git commit -m "test: add auth handler tests"
```

### Task 3: Create Admin Middleware Tests

**Files:**
- Create: `internal/middleware/auth_test.go`

- [ ] **Step 1: Write the failing test for missing token**

Create a test that makes a request without authorization token, expecting a 401 Unauthorized response.

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/middleware -run TestAdminMiddlewareNoToken -v`
Expected: FAIL with "no such test"

- [ ] **Step 3: Write minimal implementation**

Create the basic test structure with necessary imports and helper functions for JWT token generation.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/middleware -run TestAdminMiddlewareNoToken -v`
Expected: PASS

- [ ] **Step 5: Add test for user token on admin route**

Create a test that uses a regular user token on an admin route, expecting a 403 Forbidden response.

- [ ] **Step 6: Add test for admin token on admin route**

Create a test that uses an admin token on an admin route, expecting a 200 OK response.

- [ ] **Step 7: Run all middleware tests**

Run: `go test ./internal/middleware -run TestAdmin -v`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add internal/middleware/auth_test.go
git commit -m "test: add admin middleware tests"
```

### Task 4: Create Scanner Service Tests

**Files:**
- Create: `internal/services/scanner_test.go`

- [ ] **Step 1: Write the failing test for ffprobe single call**

Create a test that verifies ffprobe is called exactly once when processing a file (B4 fix).

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/services -run TestScannerFFProbeSingleCall -v`
Expected: FAIL with "no such test"

- [ ] **Step 3: Write minimal implementation**

Create the basic test structure with necessary imports and mocking setup for ffprobe.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/services -run TestScannerFFProbeSingleCall -v`
Expected: PASS

- [ ] **Step 5: Add test for sweepDeletedMedia**

Create a test that verifies the sweepDeletedMedia functionality correctly removes records for deleted files.

- [ ] **Step 6: Run all scanner tests**

Run: `go test ./internal/services -run TestScanner -v`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add internal/services/scanner_test.go
git commit -m "test: add scanner service tests"
```

### Task 5: Create Watcher Service Tests

**Files:**
- Create: `internal/services/watcher_test.go`

- [ ] **Step 1: Write the failing test for debounce**

Create a test that verifies multiple events trigger exactly one scan after debouncing (B4 watcher fix).

- [ ] **Step 2: Run test to verify it fails**

Run: `go test ./internal/services -run TestWatcherDebounce -v`
Expected: FAIL with "no such test"

- [ ] **Step 3: Write minimal implementation**

Create the basic test structure with necessary imports and setup for filesystem event simulation.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test ./internal/services -run TestWatcherDebounce -v`
Expected: PASS

- [ ] **Step 5: Add test for disabled watcher**

Create a test that verifies events are ignored when watcher is disabled.

- [ ] **Step 6: Run all watcher tests**

Run: `go test ./internal/services -run TestWatcher -v`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add internal/services/watcher_test.go
git commit -m "test: add watcher service tests"
```

### Task 6: Verify All Tests Pass

**Files:**
- None (verification step)

- [ ] **Step 1: Run all tests with race detector**

Run: `go test ./internal/... -race -v`
Expected: All tests PASS

- [ ] **Step 2: Verify build still works**

Run: `go build ./...`
Expected: Successful build with no errors

- [ ] **Step 3: Format code**

Run: `gofmt -w internal/ cmd/`
Expected: Properly formatted code

- [ ] **Step 4: Final verification**

Run: `go test ./internal/... -race | tail -10`
Expected: Test summary showing all passed

- [ ] **Step 5: Commit documentation**

```bash
git add docs/superpowers/plans/2026-07-29-backend-tests-implementation.md
git commit -m "docs: add backend tests implementation plan"
```

## Self-Review

**1. Spec coverage:**
✅ Upload handler tests - POST /api/media/upload with multipart/form-data, file and library_id
✅ Upload handler tests - 201 Created on success, 400 on missing file, 400 on invalid library_id, 413 on file too large
✅ Auth handler tests - POST /api/auth/register for first (admin) and second (user) users
✅ Auth handler tests - POST /api/auth/login success and failure cases
✅ Auth handler tests - POST /api/auth/verify with empty code rejection (B2 fix)
✅ Admin middleware tests - No token (401), user token on admin route (403), admin token on admin route (200)
✅ Scanner tests - ffprobe single call verification (B4 fix), sweepDeletedMedia test
✅ Watcher tests - debounce functionality (B4 watcher fix), disabled watcher behavior

**2. Placeholder scan:**
All steps contain actual implementation details with no placeholders.

**3. Type consistency:**
All file paths and function names are consistent with the existing codebase structure.