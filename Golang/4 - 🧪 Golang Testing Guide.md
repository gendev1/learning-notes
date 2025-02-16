
## 📋 Basics of Testing

### Test File Naming
```go
// main.go
package main

// main_test.go
package main_test  // Use separate package for black-box testing
```

### Simple Test
```go
// calculator.go
package calc

func Add(a, b int) int {
    return a + b
}

// calculator_test.go
package calc

import "testing"

func TestAdd(t *testing.T) {
    got := Add(2, 3)
    want := 5
    
    if got != want {
        t.Errorf("Add(2, 3) = %d; want %d", got, want)
    }
}
```

### Running Tests
```bash
go test ./...                    # Run all tests
go test -v ./...                # Verbose output
go test -race ./...             # Race condition detection
go test -cover ./...            # Coverage report
go test -coverprofile=c.out ./... # Coverage profile
go tool cover -html=c.out       # View coverage in browser
```

## 🧩 Table-Driven Tests
```go
func TestAdd(t *testing.T) {
    tests := []struct {
        name     string
        a, b     int
        want     int
        wantErr  bool
    }{
        {
            name: "positive numbers",
            a:    2,
            b:    3,
            want: 5,
        },
        {
            name: "negative numbers",
            a:    -2,
            b:    -3,
            want: -5,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := Add(tt.a, tt.b)
            if got != tt.want {
                t.Errorf("Add(%d, %d) = %d; want %d", 
                    tt.a, tt.b, got, tt.want)
            }
        })
    }
}
```

## 🔧 Test Helpers and Setup

### Test Helper Functions
```go
func setupTestCase(t *testing.T) func() {
    t.Helper()  // Marks this as helper function
    
    // Setup code
    db := setupTestDB()
    
    // Return cleanup function
    return func() {
        db.Close()
    }
}

func TestSomething(t *testing.T) {
    cleanup := setupTestCase(t)
    defer cleanup()
    
    // Test code
}
```

### Testing with Context
```go
func TestWithContext(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    
    // Use context in test
    result, err := DoSomethingWithContext(ctx)
    if err != nil {
        t.Fatal(err)
    }
}
```

## 🎭 Mocking

### Using Interfaces for Mocking
```go
// repository.go
type UserRepository interface {
    GetUser(id string) (*User, error)
    SaveUser(user *User) error
}

// mock_repository.go
type MockUserRepository struct {
    GetUserFunc  func(id string) (*User, error)
    SaveUserFunc func(user *User) error
}

func (m *MockUserRepository) GetUser(id string) (*User, error) {
    return m.GetUserFunc(id)
}

// test file
func TestUserService(t *testing.T) {
    mockRepo := &MockUserRepository{
        GetUserFunc: func(id string) (*User, error) {
            return &User{ID: id, Name: "Test"}, nil
        },
    }
    
    service := NewUserService(mockRepo)
    user, err := service.GetUser("123")
    // Assert results
}
```

### Using Testify/Mock
```go
import "github.com/stretchr/testify/mock"

type MockUserRepository struct {
    mock.Mock
}

func (m *MockUserRepository) GetUser(id string) (*User, error) {
    args := m.Called(id)
    return args.Get(0).(*User), args.Error(1)
}

func TestUserService_GetUser(t *testing.T) {
    mockRepo := new(MockUserRepository)
    mockRepo.On("GetUser", "123").Return(&User{ID: "123"}, nil)
    
    service := NewUserService(mockRepo)
    user, err := service.GetUser("123")
    
    mockRepo.AssertExpectations(t)
}
```

## 🔍 HTTP Testing

### Testing HTTP Handlers
```go
func TestHandler(t *testing.T) {
    // Create a request
    req := httptest.NewRequest("GET", "/api/users/123", nil)
    rec := httptest.NewRecorder()
    
    // Create handler and serve request
    handler := http.HandlerFunc(UserHandler)
    handler.ServeHTTP(rec, req)
    
    // Check response
    if rec.Code != http.StatusOK {
        t.Errorf("want status 200; got %d", rec.Code)
    }
    
    var response struct {
        User User `json:"user"`
    }
    if err := json.NewDecoder(rec.Body).Decode(&response); err != nil {
        t.Fatal(err)
    }
}
```

### Testing with Router
```go
func TestAPIEndpoint(t *testing.T) {
    router := mux.NewRouter()
    router.HandleFunc("/api/users/{id}", UserHandler)
    
    ts := httptest.NewServer(router)
    defer ts.Close()
    
    resp, err := http.Get(ts.URL + "/api/users/123")
    if err != nil {
        t.Fatal(err)
    }
    defer resp.Body.Close()
    
    // Assert response
}
```

## 📊 Benchmarking

### Basic Benchmark
```go
func BenchmarkAdd(b *testing.B) {
    for i := 0; i < b.N; i++ {
        Add(2, 3)
    }
}
```

### Benchmark with Setup
```go
func BenchmarkComplexOperation(b *testing.B) {
    // Setup
    data := setupBenchmarkData()
    
    b.ResetTimer() // Reset timer after setup
    
    for i := 0; i < b.N; i++ {
        ComplexOperation(data)
    }
}
```

## 🔄 Integration Testing

### Database Integration Test
```go
func TestUserRepository_Integration(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test")
    }
    
    db, err := sql.Open("postgres", "postgres://test:test@localhost:5432/testdb?sslmode=disable")
    if err != nil {
        t.Fatal(err)
    }
    defer db.Close()
    
    repo := NewUserRepository(db)
    
    // Run tests
    t.Run("SaveUser", func(t *testing.T) {
        user := &User{Name: "Test"}
        err := repo.SaveUser(user)
        if err != nil {
            t.Error(err)
        }
    })
}
```

### Using Test Containers
```go
import "github.com/testcontainers/testcontainers-go"

func TestWithContainer(t *testing.T) {
    ctx := context.Background()
    
    req := testcontainers.ContainerRequest{
        Image:        "postgres:13",
        ExposedPorts: []string{"5432/tcp"},
        Env: map[string]string{
            "POSTGRES_PASSWORD": "test",
            "POSTGRES_DB":      "testdb",
        },
    }
    
    container, err := testcontainers.GenericContainer(
        ctx, testcontainers.GenericContainerRequest{
            ContainerRequest: req,
            Started:         true,
        })
    if err != nil {
        t.Fatal(err)
    }
    defer container.Terminate(ctx)
    
    // Run tests
}
```

## ✨ Best Practices

1. **Test Organization**
   ```go
   func TestSomething(t *testing.T) {
       // Given
       input := "test"
       expected := "TEST"
       
       // When
       result := processString(input)
       
       // Then
       if result != expected {
           t.Errorf("got %s, want %s", result, expected)
       }
   }
   ```

2. **Test Naming**
   ```go
   func TestUser_Create_ValidInput_Success(t *testing.T) {}
   func TestUser_Create_InvalidEmail_Failure(t *testing.T) {}
   ```

3. **Parallel Tests**
   ```go
   func TestParallel(t *testing.T) {
       tests := []struct{
           name string
           // test case fields
       }{
           // test cases
       }
       
       for _, tt := range tests {
           tt := tt // Capture range variable
           t.Run(tt.name, func(t *testing.T) {
               t.Parallel() // Run tests in parallel
               // Test code
           })
       }
   }
   ```

4. **Test Fixtures**
   ```go
   // testdata/users.json
   {
       "users": [
           {"id": "1", "name": "Test User"}
       ]
   }
   
   // test file
   func loadTestData(t *testing.T) []User {
       t.Helper()
       data, err := os.ReadFile("testdata/users.json")
       if err != nil {
           t.Fatal(err)
       }
       
       var result struct {
           Users []User `json:"users"`
       }
       if err := json.Unmarshal(data, &result); err != nil {
           t.Fatal(err)
       }
       return result.Users
   }
   ```

## 🎯 Tips for Node.js Developers

1. **Testing Philosophy**
   - Go encourages table-driven tests (vs describe/it blocks)
   - Built-in testing package (vs Jest/Mocha)
   - More explicit assertion style
   - Parallel testing is opt-in

2. **Key Differences**
   ```go
   // Node.js (Jest)
   describe('User', () => {
       it('should create user', async () => {
           expect(result).toBe(expected);
       });
   });
   
   // Go
   func TestUser(t *testing.T) {
       t.Run("should create user", func(t *testing.T) {
           if result != expected {
               t.Errorf("got %v, want %v", result, expected)
           }
       })
   }
   ```

3. **Assertion Libraries**
   - Go's built-in testing package is sufficient
   - Testify provides more familiar assertions
   - No need for multiple testing frameworks

Remember:
- Keep tests simple and readable
- Use table-driven tests for multiple cases
- Write tests as documentation
- Integration tests should be separate
- Use interfaces for better mocking
- Run tests with race detector