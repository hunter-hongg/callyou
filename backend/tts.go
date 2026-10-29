package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	mimoDefaultBaseURL = "https://api.xiaomimimo.com"
	mimoDefaultModel   = "mimo-v2.5-tts"
	mimoDefaultVoice   = "mimo_default"
	mimoRequestTimeout = 30 * time.Second
	// mimoMaxResponseBody caps the decoded upstream reply; even a long WAV
	// reply stays comfortably below this limit.
	mimoMaxResponseBody = 32 << 20
)

// errMimoKeyMissing reports that MIMO_API_KEY is unset, in which case the
// TTS endpoint refuses to synthesize instead of failing with an auth error.
var errMimoKeyMissing = errors.New("MIMO_API_KEY is not configured")

// mimoClient talks to the OpenAI-compatible MiMo chat-completions endpoint
// that hosts the mimo-v2.5-tts speech synthesis model.
type mimoClient struct {
	httpClient *http.Client
	baseURL    string
	model      string
	voice      string
}

func newMimoClient() *mimoClient {
	baseURL := strings.TrimSpace(os.Getenv("MIMO_BASE_URL"))
	if baseURL == "" {
		baseURL = mimoDefaultBaseURL
	}
	model := strings.TrimSpace(os.Getenv("MIMO_TTS_MODEL"))
	if model == "" {
		model = mimoDefaultModel
	}
	voice := strings.TrimSpace(os.Getenv("MIMO_TTS_VOICE"))
	if voice == "" {
		voice = mimoDefaultVoice
	}

	return &mimoClient{
		httpClient: &http.Client{Timeout: mimoRequestTimeout},
		baseURL:    strings.TrimRight(baseURL, "/"),
		model:      model,
		voice:      voice,
	}
}

type mimoTTSRequest struct {
	Model    string          `json:"model"`
	Messages []mimoMessage   `json:"messages"`
	Audio    mimoAudioParams `json:"audio"`
}

type mimoMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type mimoAudioParams struct {
	Format string `json:"format"`
	Voice  string `json:"voice"`
}

type mimoTTSResponse struct {
	Choices []mimoChoice `json:"choices"`
}

type mimoChoice struct {
	Message *mimoChoiceMessage `json:"message"`
}

type mimoChoiceMessage struct {
	Role  string    `json:"role"`
	Audio *mimoData `json:"audio"`
}

type mimoData struct {
	ID   string `json:"id"`
	Data string `json:"data"`
}

// Synthesize turns text into a WAV recording via the MiMo speech synthesis
// endpoint. The API key is read from the MIMO_API_KEY environment variable
// on every call.
func (c *mimoClient) Synthesize(ctx context.Context, text string) ([]byte, error) {
	apiKey := strings.TrimSpace(os.Getenv("MIMO_API_KEY"))
	if apiKey == "" {
		return nil, errMimoKeyMissing
	}

	payload, err := json.Marshal(mimoTTSRequest{
		Model: c.model,
		Messages: []mimoMessage{
			{Role: "assistant", Content: text},
		},
		Audio: mimoAudioParams{Format: "wav", Voice: c.voice},
	})
	if err != nil {
		return nil, fmt.Errorf("encode TTS request: %w", err)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("build TTS request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("api-key", apiKey)

	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, fmt.Errorf("call MiMo TTS: %w", err)
	}
	defer response.Body.Close()

	body, err := io.ReadAll(io.LimitReader(response.Body, mimoMaxResponseBody))
	if err != nil {
		return nil, fmt.Errorf("read MiMo TTS response: %w", err)
	}
	if response.StatusCode != http.StatusOK {
		return nil, &mimoAPIError{
			statusCode: response.StatusCode,
			body:       strings.TrimSpace(string(body)),
		}
	}

	var parsed mimoTTSResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("parse MiMo TTS response: %w", err)
	}
	if len(parsed.Choices) == 0 || parsed.Choices[0].Message == nil || parsed.Choices[0].Message.Audio == nil {
		return nil, errors.New("MiMo TTS response contains no audio")
	}
	audio := parsed.Choices[0].Message.Audio.Data
	if audio == "" {
		return nil, errors.New("MiMo TTS returned empty audio")
	}

	decoded, err := base64.StdEncoding.DecodeString(audio)
	if err != nil {
		return nil, fmt.Errorf("decode MiMo TTS audio: %w", err)
	}
	return decoded, nil
}

// mimoAPIError is a non-2xx response from the MiMo upstream service.
type mimoAPIError struct {
	statusCode int
	body       string
}

func (e *mimoAPIError) Error() string {
	summary := e.body
	if len(summary) > 300 {
		summary = summary[:300] + "…"
	}
	return fmt.Sprintf("MiMo TTS returned HTTP %d: %s", e.statusCode, summary)
}
