package main

import (
	"errors"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
)

const (
	defaultPort     = "40128"
	sharedAccount   = "callyou"
	sharedPassword  = "123456"
	displayName     = "CallYou 课堂"
	maxTTSTextRunes = 600
	defaultDBPath   = "callyou.db"
)

func main() {
	port := listenPort()

	router, err := newRouter()
	if err != nil {
		log.Fatalf("init backend: %v", err)
	}

	server := &http.Server{
		Addr:              ":" + port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("CallYou backend listening on http://localhost:%s", port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("backend stopped: %v", err)
	}
}

func listenPort() string {
	if port := os.Getenv("PORT"); port != "" {
		return port
	}
	return defaultPort
}

// databasePath returns the SQLite file holding registered accounts,
// overridable with the CALLYOU_DB environment variable.
func databasePath() string {
	if path := strings.TrimSpace(os.Getenv("CALLYOU_DB")); path != "" {
		return path
	}
	return defaultDBPath
}

func newRouter() (*gin.Engine, error) {
	router := gin.New()
	router.Use(gin.Logger(), gin.Recovery(), cors())

	classroom := newClassroom()
	mimo := newMimoClient()
	accounts, err := newAccountRegistry(databasePath())
	if err != nil {
		return nil, err
	}
	api := router.Group("/api")
	api.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "callyou-backend",
		})
	})
	api.POST("/auth/login", handleLogin(classroom, accounts))
	api.POST("/auth/register", handleRegister(accounts))
	api.GET("/students", handleStudents(classroom))
	api.GET("/calls/pending", handlePendingCalls(classroom))
	api.POST("/calls", handleCreateCall(classroom))
	api.POST("/calls/:id/acknowledge", handleAcknowledgeCall(classroom))
	api.GET("/calls", handleCallHistory(classroom))
	api.POST("/tts", handleTTS(mimo))

	return router, nil
}

func handleLogin(classroom *Classroom, accounts *AccountRegistry) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request struct {
			Account  string `json:"account"`
			Password string `json:"password"`
		}
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式不正确"})
			return
		}

		account := strings.TrimSpace(request.Account)
		if account == "" || request.Password == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请输入课堂账号和密码"})
			return
		}
		if account == sharedAccount && request.Password == sharedPassword {
			c.JSON(http.StatusOK, gin.H{
				"account":     account,
				"displayName": displayName,
			})
			return
		}

		if students, ok := accounts.Verify(account, request.Password); ok {
			classroom.SetStudents(students)
			c.JSON(http.StatusOK, gin.H{
				"account":     account,
				"displayName": displayName,
			})
			return
		}

		c.JSON(http.StatusUnauthorized, gin.H{"error": "课堂账号或密码不正确"})
	}
}

func handleRegister(accounts *AccountRegistry) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request struct {
			Username string `json:"username"`
			Password string `json:"password"`
			Students string `json:"students"`
		}
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式不正确"})
			return
		}

		username := strings.TrimSpace(request.Username)
		switch {
		case username == "":
			c.JSON(http.StatusBadRequest, gin.H{"error": "请输入用户名"})
			return
		case utf8.RuneCountInString(username) > maxUsernameRunes:
			c.JSON(http.StatusBadRequest, gin.H{"error": "用户名过长（最多 32 个字符）"})
			return
		case request.Password == "":
			c.JSON(http.StatusBadRequest, gin.H{"error": "请输入密码"})
			return
		case utf8.RuneCountInString(request.Password) > maxPasswordRunes:
			c.JSON(http.StatusBadRequest, gin.H{"error": "密码过长（最多 64 个字符）"})
			return
		}

		students := parseStudentRoster(request.Students)
		if len(students) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请填写学生名单，一行一个姓名"})
			return
		}

		err := accounts.Register(username, request.Password, students)
		switch {
		case errors.Is(err, errUsernameTaken):
			c.JSON(http.StatusConflict, gin.H{"error": errUsernameTaken.Error()})
		case errors.Is(err, errUsernameReserved):
			c.JSON(http.StatusConflict, gin.H{"error": errUsernameReserved.Error()})
		case errors.Is(err, errTooManyStudents):
			c.JSON(http.StatusBadRequest, gin.H{"error": errTooManyStudents.Error()})
		case errors.Is(err, errStudentNameLong):
			c.JSON(http.StatusBadRequest, gin.H{"error": errStudentNameLong.Error()})
		default:
			c.JSON(http.StatusCreated, gin.H{"registered": true, "username": username})
		}
	}
}

func handleStudents(classroom *Classroom) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"students":      classroom.Students(),
			"studentOnline": classroom.StudentOnline(),
		})
	}
}

func handlePendingCalls(classroom *Classroom) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"calls": classroom.PollPendingCalls()})
	}
}

func handleCreateCall(classroom *Classroom) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request struct {
			StudentID string `json:"studentId"`
			Message   string `json:"message"`
		}
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式不正确"})
			return
		}
		if strings.TrimSpace(request.StudentID) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请选择要呼叫的学生"})
			return
		}

		call, err := classroom.CreateCall(request.StudentID, request.Message)
		switch {
		case errors.Is(err, errStudentNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		case errors.Is(err, errPendingCallExists):
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
		case errors.Is(err, errMessageTooLong):
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		case err != nil:
			c.JSON(http.StatusInternalServerError, gin.H{"error": "发起呼叫失败"})
		default:
			c.JSON(http.StatusCreated, gin.H{"call": call})
		}
	}
}

func handleAcknowledgeCall(classroom *Classroom) gin.HandlerFunc {
	return func(c *gin.Context) {
		call, err := classroom.AcknowledgeCall(c.Param("id"))
		if errors.Is(err, errCallNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "确认呼叫失败"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"call": call})
	}
}

func handleCallHistory(classroom *Classroom) gin.HandlerFunc {
	return func(c *gin.Context) {
		limit := 20
		if rawLimit := c.Query("limit"); rawLimit != "" {
			parsed, err := strconv.Atoi(rawLimit)
			if err != nil || parsed < 1 || parsed > 50 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "limit 必须是 1 到 50 之间的整数"})
				return
			}
			limit = parsed
		}

		calls := classroom.CallHistory(strings.TrimSpace(c.Query("studentId")), limit)
		c.JSON(http.StatusOK, gin.H{"calls": calls})
	}
}

func handleTTS(mimo *mimoClient) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request struct {
			Text string `json:"text"`
		}
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请求格式不正确"})
			return
		}
		if strings.TrimSpace(request.Text) == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "语音文本不能为空"})
			return
		}
		if utf8.RuneCountInString(request.Text) > maxTTSTextRunes {
			c.JSON(http.StatusBadRequest, gin.H{"error": "语音文本过长"})
			return
		}

		audio, err := mimo.Synthesize(c.Request.Context(), request.Text)
		switch {
		case errors.Is(err, errMimoKeyMissing):
			log.Printf("tts: MIMO_API_KEY is not configured")
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "MIMO_API_KEY 未配置，无法生成语音"})
		case err != nil:
			log.Printf("tts: MiMo synthesis failed: %v", err)
			c.JSON(http.StatusBadGateway, gin.H{"error": ttsErrorMessage(err)})
		default:
			c.Header("Cache-Control", "no-store")
			c.Data(http.StatusOK, "audio/wav", audio)
		}
	}
}

// ttsErrorMessage maps upstream MiMo failures to user-facing messages.
func ttsErrorMessage(err error) string {
	var upstream *mimoAPIError
	if errors.As(err, &upstream) {
		switch upstream.statusCode {
		case http.StatusUnauthorized, http.StatusForbidden:
			return "MIMO_API_KEY 鉴权失败，请检查密钥配置"
		case http.StatusTooManyRequests:
			return "语音合成请求过于频繁，请稍后重试"
		}
	}
	return "语音合成失败，请稍后重试"
}

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		allowed := origin == "" || originAllowed(origin)

		if origin != "" && allowed {
			c.Header("Access-Control-Allow-Origin", origin)
			c.Header("Vary", "Origin")
		}
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		c.Header("Access-Control-Expose-Headers", "Content-Type")

		if c.Request.Method == http.MethodOptions {
			if !allowed {
				c.AbortWithStatus(http.StatusForbidden)
				return
			}
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func originAllowed(origin string) bool {
	if configured := strings.TrimSpace(os.Getenv("CORS_ALLOWED_ORIGINS")); configured != "" {
		for _, candidate := range strings.Split(configured, ",") {
			if strings.TrimSpace(candidate) == origin {
				return true
			}
		}
		return false
	}

	parsed, err := url.Parse(origin)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return false
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "localhost" || host == "::1" || strings.HasSuffix(host, ".local") {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && (ip.IsLoopback() || ip.IsPrivate())
}
