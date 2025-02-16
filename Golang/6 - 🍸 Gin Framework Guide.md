
## 🚀 Getting Started

### Installation
```bash
go get -u github.com/gin-gonic/gin
```

### Basic Server
```go
package main

import "github.com/gin-gonic/gin"

func main() {
    // Create default gin router
    r := gin.Default()  // Includes Logger and Recovery middleware
    
    // Or create a new router without middleware
    // r := gin.New()
    
    // Define a route
    r.GET("/ping", func(c *gin.Context) {
        c.JSON(200, gin.H{
            "message": "pong",
        })
    })
    
    // Run the server
    r.Run(":8080")
}
```

## 🛣️ Routing

### Basic Routes
```go
func main() {
    r := gin.Default()
    
    // Different HTTP methods
    r.GET("/users", getUsers)
    r.POST("/users", createUser)
    r.PUT("/users/:id", updateUser)
    r.DELETE("/users/:id", deleteUser)
    
    // Handle all methods
    r.Any("/anything", func(c *gin.Context) {
        c.JSON(200, gin.H{
            "method": c.Request.Method,
        })
    })
    
    r.Run()
}
```

### Route Parameters
```go
func main() {
    r := gin.Default()
    
    // URL Parameters
    r.GET("/users/:id", func(c *gin.Context) {
        id := c.Param("id")
        c.JSON(200, gin.H{"id": id})
    })
    
    // Query Parameters
    r.GET("/search", func(c *gin.Context) {
        query := c.Query("q")        // Get query parameter
        page := c.DefaultQuery("page", "1")  // With default value
        
        c.JSON(200, gin.H{
            "query": query,
            "page": page,
        })
    })
}
```

### Route Groups
```go
func main() {
    r := gin.Default()
    
    // API v1 group
    v1 := r.Group("/api/v1")
    {
        v1.GET("/users", getUsers)
        v1.POST("/users", createUser)
        
        // Nested group
        auth := v1.Group("/auth")
        {
            auth.POST("/login", login)
            auth.POST("/register", register)
        }
    }
    
    // API v2 group
    v2 := r.Group("/api/v2")
    {
        v2.GET("/users", getUsersV2)
    }
}
```

## 📝 Request Handling

### Request Body Binding
```go
// Define structs for binding
type User struct {
    Username string `json:"username" binding:"required"`
    Email    string `json:"email" binding:"required,email"`
    Age      int    `json:"age" binding:"gte=0,lte=130"`
}

func createUser(c *gin.Context) {
    var user User
    
    // Bind JSON
    if err := c.ShouldBindJSON(&user); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    
    // Process user...
    c.JSON(200, user)
}

// Different binding methods
func handleRequest(c *gin.Context) {
    // Bind JSON
    c.ShouldBindJSON(&data)
    
    // Bind Query
    c.ShouldBindQuery(&data)
    
    // Bind Form
    c.ShouldBind(&data)
    
    // Bind URI
    c.ShouldBindUri(&data)
}
```

### File Handling
```go
func main() {
    r := gin.Default()
    
    // Single file upload
    r.POST("/upload", func(c *gin.Context) {
        file, _ := c.FormFile("file")
        
        // Save file
        c.SaveUploadedFile(file, "uploads/"+file.Filename)
        
        c.JSON(200, gin.H{
            "filename": file.Filename,
        })
    })
    
    // Multiple files
    r.POST("/uploads", func(c *gin.Context) {
        form, _ := c.MultipartForm()
        files := form.File["files"]
        
        for _, file := range files {
            c.SaveUploadedFile(file, "uploads/"+file.Filename)
        }
        
        c.JSON(200, gin.H{
            "uploaded": len(files),
        })
    })
}
```

## 🔒 Middleware

### Custom Middleware
```go
func Logger() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        
        // Process request
        c.Next()
        
        // After request
        duration := time.Since(start)
        log.Printf("Request - %s %s - %v", c.Request.Method, c.Request.URL, duration)
    }
}

func AuthRequired() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
            return
        }
        
        // Validate token...
        
        c.Next()
    }
}

func main() {
    r := gin.New() // Create without default middleware
    
    // Global middleware
    r.Use(Logger())
    
    // Group middleware
    authorized := r.Group("/auth")
    authorized.Use(AuthRequired())
    {
        authorized.GET("/profile", getProfile)
    }
}
```

### Error Handling Middleware
```go
func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Next()
        
        // Handle errors after request
        if len(c.Errors) > 0 {
            c.JSON(500, gin.H{
                "errors": c.Errors.Errors(),
            })
        }
    }
}

func main() {
    r := gin.Default()
    r.Use(ErrorHandler())
    
    r.GET("/error", func(c *gin.Context) {
        c.Error(fmt.Errorf("something went wrong"))
    })
}
```

## 🎨 Response Handling

### Different Response Types
```go
func handleResponses(c *gin.Context) {
    // JSON Response
    c.JSON(200, gin.H{
        "message": "success",
        "data": data,
    })
    
    // XML Response
    c.XML(200, gin.H{
        "message": "success",
    })
    
    // YAML Response
    c.YAML(200, gin.H{
        "message": "success",
    })
    
    // String Response
    c.String(200, "Hello %s", "World")
    
    // HTML Response
    c.HTML(200, "template.html", gin.H{
        "title": "My Page",
    })
    
    // Redirect
    c.Redirect(302, "/new-url")
}
```

### Custom Response Format
```go
type Response struct {
    Code    int         `json:"code"`
    Message string      `json:"message"`
    Data    interface{} `json:"data,omitempty"`
}

func SuccessResponse(c *gin.Context, data interface{}) {
    c.JSON(200, Response{
        Code:    200,
        Message: "success",
        Data:    data,
    })
}

func ErrorResponse(c *gin.Context, code int, message string) {
    c.JSON(code, Response{
        Code:    code,
        Message: message,
    })
}
```

## 📝 Templates

### HTML Templates
```go
func main() {
    r := gin.Default()
    
    // Load templates
    r.LoadHTMLGlob("templates/*")
    
    // Serve static files
    r.Static("/static", "./static")
    
    r.GET("/", func(c *gin.Context) {
        c.HTML(200, "index.html", gin.H{
            "title": "Home Page",
            "user":  user,
        })
    })
}
```

## 🔍 Validation

### Custom Validators
```go
type User struct {
    Username string `json:"username" binding:"required,min=4,max=20"`
    Email    string `json:"email" binding:"required,email"`
    Age      int    `json:"age" binding:"required,gte=18"`
    Password string `json:"password" binding:"required,min=8"`
}

func setupValidation() {
    if v, ok := binding.Validator.Engine().(*validator.Validate); ok {
        // Custom validation
        v.RegisterValidation("is_cool_name", func(fl validator.FieldLevel) bool {
            return strings.Contains(fl.Field().String(), "cool")
        })
    }
}
```

## 💾 Database Integration

### GORM with Gin
```go
type User struct {
    gorm.Model
    Username string `json:"username"`
    Email    string `json:"email"`
}

var db *gorm.DB

func main() {
    // Setup Database
    db, err := gorm.Open(mysql.Open("connection_string"), &gorm.Config{})
    if err != nil {
        panic("failed to connect database")
    }
    
    r := gin.Default()
    
    r.GET("/users", func(c *gin.Context) {
        var users []User
        db.Find(&users)
        
        c.JSON(200, users)
    })
    
    r.POST("/users", func(c *gin.Context) {
        var user User
        if err := c.ShouldBindJSON(&user); err != nil {
            c.JSON(400, gin.H{"error": err.Error()})
            return
        }
        
        db.Create(&user)
        c.JSON(200, user)
    })
}
```

## 🎯 Tips for Node.js Developers

1. **Express.js vs Gin**
   ```go
   // Express.js
   app.get('/users/:id', (req, res) => {
       const id = req.params.id;
       res.json({ id });
   });
   
   // Gin
   r.GET("/users/:id", func(c *gin.Context) {
       id := c.Param("id")
       c.JSON(200, gin.H{"id": id})
   })
   ```

2. **Key Differences**
   - Gin is more performant out of the box
   - Middleware syntax is similar
   - Built-in request binding and validation
   - Strong typing for everything

3. **Common Patterns**
   - Use groups for route organization
   - Implement middleware for cross-cutting concerns
   - Use binding for request validation
   - Structure handlers in separate packages

Remember:
- Use Gin's built-in features
- Leverage Go's type system
- Keep handlers small and focused
- Use middleware for common functionality
- Consider performance implications