package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

type testCall struct {
	ID             string     `json:"id"`
	StudentID      string     `json:"studentId"`
	StudentName    string     `json:"studentName"`
	Message        string     `json:"message"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"createdAt"`
	AcknowledgedAt *time.Time `json:"acknowledgedAt"`
}

func TestListenPort(t *testing.T) {
	t.Setenv("PORT", "")
	if got := listenPort(); got != defaultPort {
		t.Fatalf("listenPort() = %q, want %q", got, defaultPort)
	}

	t.Setenv("PORT", "8080")
	if got := listenPort(); got != "8080" {
		t.Fatalf("listenPort() = %q, want %q", got, "8080")
	}
}

func TestHealth(t *testing.T) {
	recorder := performJSON(t, newTestRouter(), http.MethodGet, "/api/health", nil)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}

	var response struct {
		Status  string `json:"status"`
		Service string `json:"service"`
	}
	decodeResponse(t, recorder, &response)
	if response.Status != "ok" || response.Service != "callyou-backend" {
		t.Fatalf("unexpected response: %+v", response)
	}
}

func TestLoginWithSharedAccount(t *testing.T) {
	router := newTestRouter()

	recorder := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{
		"account":  sharedAccount,
		"password": sharedPassword,
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d: %s", recorder.Code, http.StatusOK, recorder.Body.String())
	}

	var response struct {
		Account     string `json:"account"`
		DisplayName string `json:"displayName"`
	}
	decodeResponse(t, recorder, &response)
	if response.Account != sharedAccount || response.DisplayName != displayName {
		t.Fatalf("unexpected login response: %+v", response)
	}

	badLogin := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{
		"account":  sharedAccount,
		"password": "wrong",
	})
	if badLogin.Code != http.StatusUnauthorized {
		t.Fatalf("bad login status = %d, want %d", badLogin.Code, http.StatusUnauthorized)
	}

	missingFields := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{})
	if missingFields.Code != http.StatusBadRequest {
		t.Fatalf("missing fields status = %d, want %d", missingFields.Code, http.StatusBadRequest)
	}
}

func TestRegisterAndLogin(t *testing.T) {
	router := newTestRouter()

	reserved := performJSON(t, router, http.MethodPost, "/api/auth/register", map[string]string{
		"username": sharedAccount,
		"password": "x",
		"students": "张小明",
	})
	if reserved.Code != http.StatusConflict {
		t.Fatalf("reserved username status = %d, want %d: %s", reserved.Code, http.StatusConflict, reserved.Body.String())
	}

	registered := performJSON(t, router, http.MethodPost, "/api/auth/register", map[string]string{
		"username": "li",
		"password": "abc123",
		"students": "小明\n\n小红 \r\n小刚",
	})
	if registered.Code != http.StatusCreated {
		t.Fatalf("register status = %d, want %d: %s", registered.Code, http.StatusCreated, registered.Body.String())
	}
	var registeredResponse struct {
		Registered bool   `json:"registered"`
		Username   string `json:"username"`
	}
	decodeResponse(t, registered, &registeredResponse)
	if !registeredResponse.Registered || registeredResponse.Username != "li" {
		t.Fatalf("unexpected register response: %+v", registeredResponse)
	}

	duplicate := performJSON(t, router, http.MethodPost, "/api/auth/register", map[string]string{
		"username": "li",
		"password": "other",
		"students": "小明",
	})
	if duplicate.Code != http.StatusConflict {
		t.Fatalf("duplicate status = %d, want %d: %s", duplicate.Code, http.StatusConflict, duplicate.Body.String())
	}

	emptyRoster := performJSON(t, router, http.MethodPost, "/api/auth/register", map[string]string{
		"username": "wang",
		"password": "abc",
		"students": "   \n ",
	})
	if emptyRoster.Code != http.StatusBadRequest {
		t.Fatalf("empty roster status = %d, want %d", emptyRoster.Code, http.StatusBadRequest)
	}

	badLogin := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{
		"account":  "li",
		"password": "nope",
	})
	if badLogin.Code != http.StatusUnauthorized {
		t.Fatalf("bad registered login status = %d, want %d", badLogin.Code, http.StatusUnauthorized)
	}

	login := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{
		"account":  "li",
		"password": "abc123",
	})
	if login.Code != http.StatusOK {
		t.Fatalf("registered login status = %d, want %d: %s", login.Code, http.StatusOK, login.Body.String())
	}

	students := performJSON(t, router, http.MethodGet, "/api/students", nil)
	var studentsResponse struct {
		Students []Student `json:"students"`
	}
	decodeResponse(t, students, &studentsResponse)
	if len(studentsResponse.Students) != 3 {
		t.Fatalf("students = %d, want 3", len(studentsResponse.Students))
	}
	if studentsResponse.Students[0].Name != "小明" || studentsResponse.Students[2].Name != "小刚" {
		t.Fatalf("unexpected roster: %+v", studentsResponse.Students)
	}

	sharedLogin := performJSON(t, router, http.MethodPost, "/api/auth/login", map[string]string{
		"account":  sharedAccount,
		"password": sharedPassword,
	})
	if sharedLogin.Code != http.StatusOK {
		t.Fatalf("shared login after registration status = %d, want %d", sharedLogin.Code, http.StatusOK)
	}
}

func TestCallLifecycle(t *testing.T) {
	router := newTestRouter()

	recorder := performJSON(t, router, http.MethodGet, "/api/students", nil)
	if recorder.Code != http.StatusOK {
		t.Fatalf("students status = %d", recorder.Code)
	}
	var studentsResponse struct {
		Students      []Student `json:"students"`
		StudentOnline bool      `json:"studentOnline"`
	}
	decodeResponse(t, recorder, &studentsResponse)
	if len(studentsResponse.Students) != 6 {
		t.Fatalf("students = %d, want 6", len(studentsResponse.Students))
	}
	if studentsResponse.StudentOnline {
		t.Fatal("student client should start offline")
	}
	studentID := studentsResponse.Students[0].ID
	studentName := studentsResponse.Students[0].Name
	secondStudentID := studentsResponse.Students[1].ID

	pending := performJSON(t, router, http.MethodGet, "/api/calls/pending", nil)
	var pendingResponse struct {
		Calls []testCall `json:"calls"`
	}
	decodeResponse(t, pending, &pendingResponse)
	if len(pendingResponse.Calls) != 0 {
		t.Fatalf("expected no pending calls, got %+v", pendingResponse.Calls)
	}

	students := performJSON(t, router, http.MethodGet, "/api/students", nil)
	decodeResponse(t, students, &studentsResponse)
	if !studentsResponse.StudentOnline {
		t.Fatal("student polling should mark the student client online")
	}

	created := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{
		"studentId": studentID,
		"message":   "请到办公室来一下。",
	})
	if created.Code != http.StatusCreated {
		t.Fatalf("create call status = %d, want %d: %s", created.Code, http.StatusCreated, created.Body.String())
	}
	var createdResponse struct {
		Call testCall `json:"call"`
	}
	decodeResponse(t, created, &createdResponse)
	if createdResponse.Call.StudentName != studentName ||
		createdResponse.Call.Message != "请到办公室来一下。" ||
		createdResponse.Call.Status != "ringing" {
		t.Fatalf("unexpected created call: %+v", createdResponse.Call)
	}

	duplicate := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{
		"studentId": studentID,
	})
	if duplicate.Code != http.StatusConflict {
		t.Fatalf("duplicate call status = %d, want %d", duplicate.Code, http.StatusConflict)
	}

	secondCall := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{
		"studentId": secondStudentID,
		"message":   "请回答这个问题。",
	})
	if secondCall.Code != http.StatusCreated {
		t.Fatalf("second call status = %d, want %d: %s", secondCall.Code, http.StatusCreated, secondCall.Body.String())
	}
	var secondCallResponse struct {
		Call testCall `json:"call"`
	}
	decodeResponse(t, secondCall, &secondCallResponse)

	pending = performJSON(t, router, http.MethodGet, "/api/calls/pending", nil)
	decodeResponse(t, pending, &pendingResponse)
	if len(pendingResponse.Calls) != 2 {
		t.Fatalf("unified student client should receive both calls, got %+v", pendingResponse.Calls)
	}
	if pendingResponse.Calls[0].ID != secondCallResponse.Call.ID {
		t.Fatalf("pending calls should be newest first, got %+v", pendingResponse.Calls)
	}

	acknowledged := performJSON(t, router, http.MethodPost, "/api/calls/"+createdResponse.Call.ID+"/acknowledge", nil)
	if acknowledged.Code != http.StatusOK {
		t.Fatalf("ack status = %d, want %d: %s", acknowledged.Code, http.StatusOK, acknowledged.Body.String())
	}
	var acknowledgedResponse struct {
		Call testCall `json:"call"`
	}
	decodeResponse(t, acknowledged, &acknowledgedResponse)
	if acknowledgedResponse.Call.Status != "acknowledged" || acknowledgedResponse.Call.AcknowledgedAt == nil {
		t.Fatalf("call was not acknowledged: %+v", acknowledgedResponse.Call)
	}

	secondAck := performJSON(t, router, http.MethodPost, "/api/calls/"+createdResponse.Call.ID+"/acknowledge", nil)
	if secondAck.Code != http.StatusOK {
		t.Fatalf("idempotent ack status = %d, want %d", secondAck.Code, http.StatusOK)
	}

	unknownAck := performJSON(t, router, http.MethodPost, "/api/calls/call-missing/acknowledge", nil)
	if unknownAck.Code != http.StatusNotFound {
		t.Fatalf("unknown call ack status = %d, want %d", unknownAck.Code, http.StatusNotFound)
	}

	pending = performJSON(t, router, http.MethodGet, "/api/calls/pending", nil)
	decodeResponse(t, pending, &pendingResponse)
	if len(pendingResponse.Calls) != 1 || pendingResponse.Calls[0].ID != secondCallResponse.Call.ID {
		t.Fatalf("acknowledged call should leave pending, got %+v", pendingResponse.Calls)
	}

	history := performJSON(t, router, http.MethodGet, "/api/calls?studentId="+studentID, nil)
	if history.Code != http.StatusOK {
		t.Fatalf("history status = %d", history.Code)
	}
	var historyResponse struct {
		Calls []testCall `json:"calls"`
	}
	decodeResponse(t, history, &historyResponse)
	if len(historyResponse.Calls) != 1 || historyResponse.Calls[0].Status != "acknowledged" {
		t.Fatalf("unexpected history: %+v", historyResponse.Calls)
	}
}

func TestCreateCallValidation(t *testing.T) {
	router := newTestRouter()

	missingStudent := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{})
	if missingStudent.Code != http.StatusBadRequest {
		t.Fatalf("missing student status = %d, want %d", missingStudent.Code, http.StatusBadRequest)
	}

	unknownStudent := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{
		"studentId": "missing",
	})
	if unknownStudent.Code != http.StatusNotFound {
		t.Fatalf("unknown student status = %d, want %d", unknownStudent.Code, http.StatusNotFound)
	}

	longMessage := make([]rune, maxCallMessageRunes+1)
	for index := range longMessage {
		longMessage[index] = '呼'
	}
	tooLong := performJSON(t, router, http.MethodPost, "/api/calls", map[string]string{
		"studentId": "student-1",
		"message":   string(longMessage),
	})
	if tooLong.Code != http.StatusBadRequest {
		t.Fatalf("long message status = %d, want %d", tooLong.Code, http.StatusBadRequest)
	}

	invalidLimit := performJSON(t, router, http.MethodGet, "/api/calls?limit=0", nil)
	if invalidLimit.Code != http.StatusBadRequest {
		t.Fatalf("invalid limit status = %d, want %d", invalidLimit.Code, http.StatusBadRequest)
	}
}

func TestTTSRejectsInvalidText(t *testing.T) {
	router := newTestRouter()

	empty := performJSON(t, router, http.MethodPost, "/api/tts", map[string]string{"text": " "})
	if empty.Code != http.StatusBadRequest {
		t.Fatalf("empty tts text status = %d, want %d", empty.Code, http.StatusBadRequest)
	}

	longText := make([]rune, maxTTSTextRunes+1)
	for index := range longText {
		longText[index] = '呼'
	}
	tooLong := performJSON(t, router, http.MethodPost, "/api/tts", map[string]string{"text": string(longText)})
	if tooLong.Code != http.StatusBadRequest {
		t.Fatalf("long tts text status = %d, want %d", tooLong.Code, http.StatusBadRequest)
	}
}

func TestTTSWithoutAPIKey(t *testing.T) {
	t.Setenv("MIMO_API_KEY", "")
	router := newTestRouter()

	recorder := performJSON(t, router, http.MethodPost, "/api/tts", map[string]string{
		"text": "张小明同学，老师正在呼叫你。",
	})
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("tts status = %d, want %d: %s", recorder.Code, http.StatusServiceUnavailable, recorder.Body.String())
	}

	var response struct {
		Error string `json:"error"`
	}
	decodeResponse(t, recorder, &response)
	if !strings.Contains(response.Error, "MIMO_API_KEY") {
		t.Fatalf("error = %q, want a MIMO_API_KEY hint", response.Error)
	}
}

func TestTTSWithMiMoAPI(t *testing.T) {
	t.Setenv("MIMO_API_KEY", "test-key")

	var gotPath, gotKey, gotModel, gotVoice, gotText string
	fakeMimo := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotKey = r.Header.Get("api-key")

		var payload mimoTTSRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		gotModel = payload.Model
		gotVoice = payload.Audio.Voice
		if len(payload.Messages) > 0 {
			gotText = payload.Messages[0].Content
		}

		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"model": "mimo-v2.5-tts",
			"choices": []map[string]any{
				{
					"finish_reason": "stop",
					"message": map[string]any{
						"role": "assistant",
						"audio": map[string]any{
							"id":   "audio-1",
							"data": base64.StdEncoding.EncodeToString([]byte("RIFF-fake-wav")),
						},
					},
				},
			},
		})
	}))
	defer fakeMimo.Close()
	t.Setenv("MIMO_BASE_URL", fakeMimo.URL)

	router := newTestRouter()
	recorder := performJSON(t, router, http.MethodPost, "/api/tts", map[string]string{
		"text": "张小明同学，老师正在呼叫你。",
	})
	if recorder.Code != http.StatusOK {
		t.Fatalf("tts status = %d, want %d: %s", recorder.Code, http.StatusOK, recorder.Body.String())
	}
	if contentType := recorder.Header().Get("Content-Type"); contentType != "audio/wav" {
		t.Fatalf("Content-Type = %q, want audio/wav", contentType)
	}
	if got := recorder.Body.String(); got != "RIFF-fake-wav" {
		t.Fatalf("audio body = %q, want the decoded upstream audio", got)
	}
	if empty := recorder.Header().Get("X-TTS-Audio-Empty"); empty != "" {
		t.Fatalf("X-TTS-Audio-Empty = %q, want the header to be absent", empty)
	}

	if gotPath != "/v1/chat/completions" {
		t.Fatalf("upstream path = %q, want /v1/chat/completions", gotPath)
	}
	if gotKey != "test-key" {
		t.Fatalf("upstream api-key header = %q, want test-key", gotKey)
	}
	if gotModel != "mimo-v2.5-tts" {
		t.Fatalf("upstream model = %q, want mimo-v2.5-tts", gotModel)
	}
	if gotVoice != "mimo_default" {
		t.Fatalf("upstream voice = %q, want mimo_default", gotVoice)
	}
	if gotText != "张小明同学，老师正在呼叫你。" {
		t.Fatalf("upstream text = %q, want the requested text", gotText)
	}
}

func TestTTSUpstreamAuthenticationFailure(t *testing.T) {
	t.Setenv("MIMO_API_KEY", "test-key")

	fakeMimo := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":{"message":"invalid api key"}}`))
	}))
	defer fakeMimo.Close()
	t.Setenv("MIMO_BASE_URL", fakeMimo.URL)

	router := newTestRouter()
	recorder := performJSON(t, router, http.MethodPost, "/api/tts", map[string]string{
		"text": "张小明同学",
	})
	if recorder.Code != http.StatusBadGateway {
		t.Fatalf("tts status = %d, want %d: %s", recorder.Code, http.StatusBadGateway, recorder.Body.String())
	}

	var response struct {
		Error string `json:"error"`
	}
	decodeResponse(t, recorder, &response)
	if !strings.Contains(response.Error, "MIMO_API_KEY") {
		t.Fatalf("error = %q, want a MIMO_API_KEY hint", response.Error)
	}
}

func TestCORSAllowsLocalOriginsOnly(t *testing.T) {
	t.Setenv("CORS_ALLOWED_ORIGINS", "")
	router := newTestRouter()

	allowed := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodOptions, "/api/students", nil)
	request.Header.Set("Origin", "http://localhost:5173")
	router.ServeHTTP(allowed, request)
	if allowed.Code != http.StatusNoContent {
		t.Fatalf("allowed status = %d, want %d", allowed.Code, http.StatusNoContent)
	}
	if got := allowed.Header().Get("Access-Control-Allow-Origin"); got != "http://localhost:5173" {
		t.Fatalf("Access-Control-Allow-Origin = %q", got)
	}

	privateNetwork := httptest.NewRecorder()
	request = httptest.NewRequest(http.MethodOptions, "/api/students", nil)
	request.Header.Set("Origin", "http://192.168.1.20:8080")
	router.ServeHTTP(privateNetwork, request)
	if privateNetwork.Code != http.StatusNoContent {
		t.Fatalf("private network status = %d, want %d", privateNetwork.Code, http.StatusNoContent)
	}

	blocked := httptest.NewRecorder()
	request = httptest.NewRequest(http.MethodOptions, "/api/students", nil)
	request.Header.Set("Origin", "https://example.com")
	router.ServeHTTP(blocked, request)
	if blocked.Code != http.StatusForbidden {
		t.Fatalf("blocked status = %d, want %d", blocked.Code, http.StatusForbidden)
	}
	if got := blocked.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("blocked origin header = %q, want empty", got)
	}
}

func newTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	os.Setenv("CALLYOU_DB", ":memory:")
	router, err := newRouter()
	if err != nil {
		panic(fmt.Sprintf("newTestRouter: %v", err))
	}
	return router
}

func performJSON(t *testing.T, router http.Handler, method, path string, payload any) *httptest.ResponseRecorder {
	t.Helper()

	var body *bytes.Reader
	if payload == nil {
		body = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("encode request: %v", err)
		}
		body = bytes.NewReader(encoded)
	}

	request := httptest.NewRequest(method, path, body)
	if payload != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	return recorder
}

func decodeResponse(t *testing.T, recorder *httptest.ResponseRecorder, target any) {
	t.Helper()
	if err := json.NewDecoder(recorder.Body).Decode(target); err != nil {
		t.Fatalf("decode response: %v", err)
	}
}
