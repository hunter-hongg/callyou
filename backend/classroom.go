package main

import (
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	studentOnlineWindow = 10 * time.Second
	defaultCallMessage  = "老师正在呼叫你，请尽快回应。"
	maxCallMessageRunes = 200
	maxCallHistory      = 500
)

var (
	errStudentNotFound   = errors.New("未找到该学生")
	errPendingCallExists = errors.New("该学生已有待确认的呼叫")
	errCallNotFound      = errors.New("未找到该呼叫")
	errMessageTooLong    = errors.New("呼叫说明不能超过 200 个字符")
)

type Student struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Call struct {
	ID             string     `json:"id"`
	StudentID      string     `json:"studentId"`
	StudentName    string     `json:"studentName"`
	Message        string     `json:"message"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"createdAt"`
	AcknowledgedAt *time.Time `json:"acknowledgedAt,omitempty"`
}

type studentRecord struct {
	id   string
	name string
}

type Classroom struct {
	mu              sync.Mutex
	students        []*studentRecord
	byID            map[string]*studentRecord
	calls           []*Call
	nextCall        uint64
	now             func() time.Time
	onlineFor       time.Duration
	studentLastSeen time.Time
}

func newClassroom() *Classroom {
	classroom := &Classroom{
		byID:      make(map[string]*studentRecord),
		now:       time.Now,
		onlineFor: studentOnlineWindow,
	}

	for index, name := range []string{
		"张小明",
		"李思思",
		"王一诺",
		"陈子涵",
		"刘星辰",
		"赵雨桐",
	} {
		student := &studentRecord{
			id:   fmt.Sprintf("student-%d", index+1),
			name: name,
		}
		classroom.students = append(classroom.students, student)
		classroom.byID[student.id] = student
	}

	return classroom
}

// SetStudents replaces the current roster with the given names, used when
// a registered account logs in with its own student roster.
func (c *Classroom) SetStudents(names []string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.students = nil
	c.byID = make(map[string]*studentRecord)
	for index, name := range names {
		student := &studentRecord{
			id:   fmt.Sprintf("student-%d", index+1),
			name: name,
		}
		c.students = append(c.students, student)
		c.byID[student.id] = student
	}
}

func (c *Classroom) Students() []Student {
	c.mu.Lock()
	defer c.mu.Unlock()

	students := make([]Student, 0, len(c.students))
	for _, record := range c.students {
		students = append(students, Student{ID: record.id, Name: record.name})
	}
	return students
}

// StudentOnline reports whether the shared student client polled recently.
func (c *Classroom) StudentOnline() bool {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := c.now()
	return !c.studentLastSeen.IsZero() && now.Sub(c.studentLastSeen) <= c.onlineFor
}

// PollPendingCalls marks the student client online and returns every call
// that has not been acknowledged yet, newest first.
func (c *Classroom) PollPendingCalls() []Call {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.studentLastSeen = c.now()

	calls := make([]Call, 0, len(c.calls))
	for index := len(c.calls) - 1; index >= 0; index-- {
		call := c.calls[index]
		if call.AcknowledgedAt == nil {
			calls = append(calls, *call)
		}
	}
	return calls
}

func (c *Classroom) CreateCall(studentID, message string) (Call, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	record, ok := c.byID[studentID]
	if !ok {
		return Call{}, errStudentNotFound
	}

	message = strings.TrimSpace(message)
	if message == "" {
		message = defaultCallMessage
	}
	if utf8.RuneCountInString(message) > maxCallMessageRunes {
		return Call{}, errMessageTooLong
	}

	for _, call := range c.calls {
		if call.StudentID == studentID && call.AcknowledgedAt == nil {
			return Call{}, errPendingCallExists
		}
	}

	c.nextCall++
	call := &Call{
		ID:          fmt.Sprintf("call-%d", c.nextCall),
		StudentID:   record.id,
		StudentName: record.name,
		Message:     message,
		Status:      "ringing",
		CreatedAt:   c.now(),
	}
	c.calls = append(c.calls, call)
	if len(c.calls) > maxCallHistory {
		c.calls = c.calls[len(c.calls)-maxCallHistory:]
	}

	return *call, nil
}

func (c *Classroom) AcknowledgeCall(callID string) (Call, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	for _, call := range c.calls {
		if call.ID != callID {
			continue
		}
		if call.AcknowledgedAt == nil {
			now := c.now()
			call.AcknowledgedAt = &now
			call.Status = "acknowledged"
		}
		return *call, nil
	}
	return Call{}, errCallNotFound
}

func (c *Classroom) CallHistory(studentID string, limit int) []Call {
	c.mu.Lock()
	defer c.mu.Unlock()

	calls := make([]Call, 0, limit)
	for index := len(c.calls) - 1; index >= 0 && len(calls) < limit; index-- {
		call := c.calls[index]
		if studentID != "" && call.StudentID != studentID {
			continue
		}
		calls = append(calls, *call)
	}
	return calls
}
