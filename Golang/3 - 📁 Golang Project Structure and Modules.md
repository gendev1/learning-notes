

## 📦 Module Basics

### Creating a New Module
```bash
# Initialize a new module
go mod init github.com/username/project

# go.mod file is created:
module github.com/username/project
go 1.21  # Go version
```

### Managing Dependencies
```bash
# Add dependency
go get github.com/pkg/errors

# Update dependencies
go get -u ./...         # Update all
go get -u package-name  # Update specific

# Clean up unused dependencies
go mod tidy

# Verify dependencies
go mod verify
```

## 🏗️ Standard Project Layout

```
project-root/
├── .github/                    # GitHub Actions, templates
├── cmd/                        # Main applications
│   ├── api/                   # API server
│   │   └── main.go
│   └── worker/               # Background worker
│       └── main.go
├── internal/                  # Private code
│   ├── auth/                 # Authentication package
│   ├── middleware/           # HTTP middleware
│   └── models/               # Domain models
├── pkg/                      # Public code
│   ├── logger/              # Logging package
│   └── config/              # Configuration package
├── api/                      # API contracts
│   ├── swagger/             # Swagger/OpenAPI specs
│   └── protobuf/            # Protocol buffer specs
├── web/                      # Web assets
│   ├── templates/           # HTML templates
│   ├── static/              # Static files
│   └── spa/                 # Single page application
├── configs/                  # Configuration files
├── deployments/             # Deployment configurations
│   ├── docker/             # Docker files
│   └── kubernetes/         # Kubernetes manifests
├── docs/                    # Documentation
├── scripts/                 # Build/maintenance scripts
├── test/                    # Additional test files
├── tools/                   # Project tools
├── .gitignore
├── README.md
├── Makefile
├── go.mod
└── go.sum
```

## 📋 Package Organization Best Practices

### 1. Command Package (cmd/)
```go
// cmd/api/main.go
package main

import (
    "github.com/username/project/internal/server"
    "github.com/username/project/pkg/config"
)

func main() {
    cfg := config.Load()
    srv := server.New(cfg)
    srv.Start()
}
```

### 2. Internal Package
```go
// internal/models/user.go
package models

type User struct {
    ID    string
    Name  string
    Email string
}

// internal/server/server.go
package server

type Server struct {
    config Config
    router Router
}

func New(cfg Config) *Server {
    return &Server{
        config: cfg,
        router: newRouter(),
    }
}
```

### 3. Public Package (pkg/)
```go
// pkg/logger/logger.go
package logger

type Logger struct {
    level string
}

func New(level string) *Logger {
    return &Logger{level: level}
}

// pkg/config/config.go
package config

type Config struct {
    Port     int
    Database DatabaseConfig
}

func Load() Config {
    // Load configuration
}
```

## 🏗️ Project Architecture Patterns

### MVC Pattern Structure
```
project-root/
├── cmd/
│   └── api/
│       └── main.go
├── internal/
│   ├── models/              # Data models
│   │   ├── user.go
│   │   └── product.go
│   ├── controllers/         # Request handlers
│   │   ├── user.go
│   │   └── product.go
│   └── views/              # Template rendering (if applicable)
│       └── templates/
├── pkg/
│   └── middleware/
└── platform/              # Infrastructure code
    └── database/
```

### 🎯 Domain-Driven Design Structure
For larger applications, consider organizing by domain:

```
project-root/
├── cmd/
│   └── api/
│       └── main.go
├── internal/
│   ├── user/                  # User domain
│   │   ├── delivery/         # HTTP/gRPC handlers
│   │   ├── repository/       # Data access
│   │   ├── usecase/         # Business logic
│   │   └── entity.go        # Domain entity
│   ├── order/                # Order domain
│   │   ├── delivery/
│   │   ├── repository/
│   │   ├── usecase/
│   │   └── entity.go
│   └── common/              # Shared code
└── pkg/
    └── middleware/
```

## 🔄 Dependency Injection Pattern
```go
// internal/user/repository/repository.go
type Repository interface {
    GetByID(id string) (*User, error)
    Save(user *User) error
}

// internal/user/usecase/usecase.go
type UseCase interface {
    GetUser(id string) (*User, error)
    CreateUser(user *User) error
}

type userUseCase struct {
    repo Repository
}

func NewUserUseCase(repo Repository) UseCase {
    return &userUseCase{repo: repo}
}

// internal/user/delivery/http/handler.go
type Handler struct {
    useCase UseCase
}

func NewHandler(useCase UseCase) *Handler {
    return &Handler{useCase: useCase}
}
```

## 📝 Module Best Practices

### 1. Version Management
```go
// go.mod
module github.com/username/project/v2  // Use v2+ for breaking changes

require (
    github.com/pkg/errors v0.9.1
    go.uber.org/zap v1.24.0
)
```

### 2. Private Packages (internal/)
```go
// Only accessible within the same module
internal/
    ├── auth/
    │   └── auth.go       // Package auth
    └── middleware/
        └── middleware.go // Package middleware
```

### 3. Workspace Setup (go.work)
```
// go.work
go 1.21

use (
    ./project1
    ./project2
    ./shared
)
```

## 🛠️ Tools and Configuration

### 1. Makefile Example
```makefile
# Common commands
.PHONY: build test lint clean run migrate docker

# Build binary
build:
    go build -o bin/ ./cmd/...

# Run tests with race detection
test:
    go test -v -race ./...
    go test -v -cover ./...

# Run linter
lint:
    golangci-lint run
    go vet ./...

# Clean built binaries
clean:
    rm -rf bin/
    rm -rf dist/

# Run application
run:
    go run ./cmd/api/main.go

# Database migrations
migrate-up:
    migrate -path db/migrations -database "$DB_URL" up

migrate-down:
    migrate -path db/migrations -database "$DB_URL" down

# Docker commands
docker-build:
    docker build -t myapp .

docker-run:
    docker run -p 8080:8080 myapp

# Generate code (e.g., mocks, protobuf)
generate:
    go generate ./...
    mockgen -source=internal/domain/repository.go -destination=internal/mocks/repository.go

# Development tools installation
install-tools:
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    go install github.com/golang/mock/mockgen@latest

.DEFAULT_GOAL := build
```

### 2. Docker Setup
```dockerfile
# Multi-stage build
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o main ./cmd/api

FROM alpine:latest
COPY --from=builder /app/main /app/main
CMD ["/app/main"]
```

## 🎯 Domain-Driven Design Best Practices

### 1. Layer Separation
```go
// domain/user/entity.go - Domain entities
package user

type User struct {
    ID       string
    Name     string
    Email    string
    Password string
}

// domain/user/repository.go - Repository interface
type Repository interface {
    GetByID(ctx context.Context, id string) (*User, error)
    Save(ctx context.Context, user *User) error
}

// domain/user/usecase.go - Business logic interface
type UseCase interface {
    GetUser(ctx context.Context, id string) (*User, error)
    CreateUser(ctx context.Context, input CreateUserInput) (*User, error)
}
```

### 2. Clean Architecture Implementation
```go
// infrastructure/postgres/user_repository.go
package postgres

type userRepository struct {
    db *sql.DB
}

func (r *userRepository) GetByID(ctx context.Context, id string) (*user.User, error) {
    // Implementation
}

// usecase/user/user_usecase.go
type userUseCase struct {
    repo           user.Repository
    validator      validator.Interface
    eventPublisher event.Publisher
}

func (uc *userUseCase) CreateUser(ctx context.Context, input CreateUserInput) (*user.User, error) {
    // Business logic implementation
}

// delivery/http/user_handler.go
type UserHandler struct {
    useCase user.UseCase
}

func (h *UserHandler) Create(w http.ResponseWriter, r *http.Request) {
    // HTTP handling
}
```

### 3. Dependency Rules
- Dependencies flow inward: delivery → usecase → domain
- Domain package has no external dependencies
- Each layer depends only on its interfaces

### 4. Domain Service Pattern
```go
// domain/order/service.go
type OrderService interface {
    CalculateTotal(order *Order, products []*product.Product) (decimal.Decimal, error)
    ValidateOrder(order *Order) error
}

type orderService struct {
    productRepo product.Repository
    taxService  tax.Service
}
```

### 5. Value Objects
```go
// domain/value_objects.go
type Email struct {
    value string
}

func NewEmail(email string) (Email, error) {
    // Validation logic
}

type Money struct {
    Amount   decimal.Decimal
    Currency string
}
```

### 6. Domain Events
```go
// domain/events/user_events.go
type UserCreated struct {
    ID        string
    Email     string
    Timestamp time.Time
}

// usecase/user/user_usecase.go
func (uc *userUseCase) CreateUser(ctx context.Context, input CreateUserInput) (*user.User, error) {
    u := user.New(input)
    if err := uc.repo.Save(ctx, u); err != nil {
        return nil, err
    }
    
    uc.eventPublisher.Publish(events.UserCreated{
        ID:        u.ID,
        Email:     u.Email,
        Timestamp: time.Now(),
    })
    return u, nil
}
```

### 7. Error Handling
```go
// domain/errors/errors.go
type DomainError struct {
    Code    string
    Message string
}

var (
    ErrUserNotFound     = &DomainError{Code: "USER_NOT_FOUND", Message: "user not found"}
    ErrInvalidEmail     = &DomainError{Code: "INVALID_EMAIL", Message: "invalid email format"}
    ErrDuplicateEmail   = &DomainError{Code: "DUPLICATE_EMAIL", Message: "email already exists"}
)
```

### 8. Configuration Management
```go
// config/config.go
type Config struct {
    HTTP     HTTPConfig
    Database DatabaseConfig
    Cache    CacheConfig
}

// infrastructure/container/container.go
type Container struct {
    Config     *config.Config
    DB         *sql.DB
    Redis      *redis.Client
    UserRepo   user.Repository
    UserUseCase user.UseCase
}

func NewContainer(cfg *config.Config) (*Container, error) {
    // Initialize dependencies
}
```

## 💡 Tips for Node.js Developers

1. **Package Organization**
   - No `node_modules/` - Go modules are in `$GOPATH`
   - No `package.json` - Use `go.mod` instead
   - No `src/` directory - Use `cmd/`, `internal/`, `pkg/`

2. **Module System**
   - More explicit than Node.js
   - Version in import path for major versions
   - Better dependency management

3. **Project Structure**
   - More opinionated than Node.js
   - Clear separation of public/private code
   - Domain-driven by default

4. **Configuration**
   - Use environment variables or config files
   - No `.env` file by default
   - Strong typing for config

Remember:
- Keep packages small and focused
- Use `internal/` for private code
- Follow standard project layout
- Use domain-driven design for larger apps
- Leverage Go modules for dependency management