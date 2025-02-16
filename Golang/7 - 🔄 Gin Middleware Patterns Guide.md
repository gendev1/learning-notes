

## 🎯 Basic Middleware Structure

### Simple Middleware Template
```go
func BasicMiddleware() gin.HandlerFunc {
    // Perform setup operations here
    return func(c *gin.Context) {
        // Before request
        
        c.Next()  // Process request
        
        // After request
    }
}
```

### With Configuration Options
```go
type MiddlewareConfig struct {
    // Configuration fields
    EnableLogging bool
    TimeoutSeconds int
    AllowedOrigins []string
}

func ConfigurableMiddleware(config MiddlewareConfig) gin.HandlerFunc {
    // Initialize with config
    return func(c *gin.Context) {
        // Use config in middleware
        if config.EnableLogging {
            // Log request
        }
        c.Next()
    }
}

// Usage
r.Use(ConfigurableMiddleware(MiddlewareConfig{
    EnableLogging: true,
    TimeoutSeconds: 30,
}))
```

## 🔒 Authentication Patterns

### JWT Authentication
```go
type Claims struct {
    UserID uint   `json:"user_id"`
    Role   string `json:"role"`
    jwt.StandardClaims
}

func JWTMiddleware(secret string) gin.HandlerFunc {
    return func(c *gin.Context) {
        tokenString := c.GetHeader("Authorization")
        if tokenString == "" {
            c.AbortWithStatusJSON(401, gin.H{"error": "no token provided"})
            return
        }

        // Remove 'Bearer ' prefix
        tokenString = strings.Replace(tokenString, "Bearer ", "", 1)

        claims := &Claims{}
        token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
            return []byte(secret), nil
        })

        if err != nil || !token.Valid {
            c.AbortWithStatusJSON(401, gin.H{"error": "invalid token"})
            return
        }

        // Set claims to context
        c.Set("userID", claims.UserID)
        c.Set("role", claims.Role)
        
        c.Next()
    }
}
```

### Role-Based Authorization
```go
func RoleAuthMiddleware(roles ...string) gin.HandlerFunc {
    return func(c *gin.Context) {
        userRole, exists := c.Get("role")
        if !exists {
            c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
            return
        }

        for _, role := range roles {
            if role == userRole.(string) {
                c.Next()
                return
            }
        }

        c.AbortWithStatusJSON(403, gin.H{"error": "forbidden"})
    }
}

// Usage
r.GET("/admin", 
    JWTMiddleware(secretKey),
    RoleAuthMiddleware("admin"),
    adminHandler,
)
```

## 📊 Logging and Monitoring

### Advanced Logger
```go
func AdvancedLogger() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Start timer
        start := time.Now()
        path := c.Request.URL.Path
        raw := c.Request.URL.RawQuery

        // Process request
        c.Next()

        // Stop timer
        stop := time.Now()
        latency := stop.Sub(start)

        // Get status
        status := c.Writer.Status()
        
        // Get error if exists
        var errorMessage string
        if len(c.Errors) > 0 {
            errorMessage = c.Errors.String()
        }

        log.Printf("[GIN] %v | %3d | %13v | %15s | %-7s %s%s | %s",
            stop.Format("2006/01/02 - 15:04:05"),
            status,
            latency,
            c.ClientIP(),
            c.Request.Method,
            path,
            raw,
            errorMessage,
        )
    }
}
```

### Prometheus Metrics
```go
func PrometheusMiddleware() gin.HandlerFunc {
    httpRequestsTotal := prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "path", "status"},
    )
    prometheus.MustRegister(httpRequestsTotal)

    return func(c *gin.Context) {
        path := c.Request.URL.Path
        method := c.Request.Method

        c.Next()

        status := strconv.Itoa(c.Writer.Status())
        httpRequestsTotal.WithLabelValues(method, path, status).Inc()
    }
}
```

## 🔄 Error Handling

### Global Error Handler
```go
type AppError struct {
    Code    int
    Message string
}

func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Next()

        // Check if there are any errors
        if len(c.Errors) > 0 {
            for _, e := range c.Errors {
                // Check error type
                if appErr, ok := e.Err.(*AppError); ok {
                    c.JSON(appErr.Code, gin.H{
                        "error": appErr.Message,
                    })
                    return
                }
            }

            // Default error response
            c.JSON(500, gin.H{
                "error": "Internal Server Error",
            })
        }
    }
}

// Usage
func someHandler(c *gin.Context) {
    if err := doSomething(); err != nil {
        c.Error(&AppError{
            Code:    400,
            Message: "Something went wrong",
        })
        return
    }
}
```

## 🚦 Rate Limiting

### Token Bucket Rate Limiter
```go
func RateLimiter(limit int, burst int) gin.HandlerFunc {
    limiter := rate.NewLimiter(rate.Limit(limit), burst)
    
    return func(c *gin.Context) {
        if !limiter.Allow() {
            c.AbortWithStatusJSON(429, gin.H{
                "error": "too many requests",
            })
            return
        }
        c.Next()
    }
}

// Per-Client Rate Limiter
func PerClientRateLimiter(limit int, burst int) gin.HandlerFunc {
    limiters := make(map[string]*rate.Limiter)
    mu := &sync.RWMutex{}

    return func(c *gin.Context) {
        clientIP := c.ClientIP()
        
        mu.Lock()
        limiter, exists := limiters[clientIP]
        if !exists {
            limiter = rate.NewLimiter(rate.Limit(limit), burst)
            limiters[clientIP] = limiter
        }
        mu.Unlock()

        if !limiter.Allow() {
            c.AbortWithStatusJSON(429, gin.H{
                "error": "too many requests",
            })
            return
        }
        c.Next()
    }
}
```

## 🔍 Request/Response Modification

### Request ID Tracker
```go
func RequestIDMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Generate UUID for request
        requestID := uuid.New().String()
        
        // Set request ID in header
        c.Writer.Header().Set("X-Request-ID", requestID)
        
        // Set in context for logging
        c.Set("RequestID", requestID)
        
        c.Next()
    }
}
```

### Response Transformer
```go
func ResponseTransformer() gin.HandlerFunc {
    return func(c *gin.Context) {
        // Store the original writer
        blw := &bodyLogWriter{body: bytes.NewBufferString(""), ResponseWriter: c.Writer}
        c.Writer = blw

        c.Next()

        // Modify response after handler
        body := blw.body.String()
        
        // Transform response if needed
        newBody := transform(body)
        
        // Write the modified response
        c.Writer.Write([]byte(newBody))
    }
}

type bodyLogWriter struct {
    gin.ResponseWriter
    body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
    w.body.Write(b)
    return w.ResponseWriter.Write(b)
}
```

## 🔄 Recovery and Timeout

### Advanced Recovery
```go
func AdvancedRecovery() gin.HandlerFunc {
    return func(c *gin.Context) {
        defer func() {
            if err := recover(); err != nil {
                // Get stack trace
                stack := debug.Stack()
                
                // Log the error and stack trace
                log.Printf("panic recovered: %v\n%s", err, stack)
                
                // Notify error tracking service
                notifyErrorService(err, stack)
                
                c.AbortWithStatusJSON(500, gin.H{
                    "error": "Internal Server Error",
                })
            }
        }()
        
        c.Next()
    }
}
```

### Context Timeout
```go
func TimeoutMiddleware(timeout time.Duration) gin.HandlerFunc {
    return func(c *gin.Context) {
        // Wrap the request in a timeout context
        ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)
        defer cancel()

        // Update the request context
        c.Request = c.Request.WithContext(ctx)

        // Channel to track completion
        done := make(chan bool, 1)
        go func() {
            c.Next()
            done <- true
        }()

        select {
        case <-done:
            return
        case <-ctx.Done():
            c.AbortWithStatusJSON(408, gin.H{
                "error": "request timeout",
            })
            return
        }
    }
}
```

## 🎯 Tips and Best Practices

1. **Middleware Order**
   ```go
   func main() {
       r := gin.New()
       
       // Order matters!
       r.Use(RequestIDMiddleware())    // 1. Generate request ID
       r.Use(AdvancedLogger())        // 2. Log request (with ID)
       r.Use(ErrorHandler())          // 3. Handle errors
       r.Use(RateLimiter(100, 10))    // 4. Rate limiting
       r.Use(JWTMiddleware("secret")) // 5. Authentication
   }
   ```

2. **Context Storage**
   ```go
   // Store data safely
   func SafeContextStorage() gin.HandlerFunc {
       return func(c *gin.Context) {
           // Use type-safe keys
           type ContextKey string
           const UserKey ContextKey = "user"
           
           c.Set(string(UserKey), user)
           c.Next()
       }
   }
   ```

3. **Middleware Chaining**
   ```go
   func CombinedMiddleware(handlers ...gin.HandlerFunc) gin.HandlerFunc {
       return func(c *gin.Context) {
           for _, h := range handlers {
               h(c)
               if c.IsAborted() {
                   return
               }
           }
       }
   }
   ```

Remember:
- Keep middleware focused and single-purpose
- Consider performance implications
- Use proper error handling
- Maintain request context
- Order middleware logically
- Use configuration when needed