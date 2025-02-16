

## 🚀 Setup and Configuration

### Basic Setup
```go
package main

import (
    "context"
    "log"
    "time"
    
    "github.com/gin-gonic/gin"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
)

// Database instance
type MongoInstance struct {
    Client *mongo.Client
    DB     *mongo.Database
}

var MI MongoInstance

// Database settings
const (
    DATABASE = "go_demo"
    TIMEOUT  = 10 * time.Second
)

func ConnectDB() error {
    client, err := mongo.NewClient(options.Client().ApplyURI("mongodb://localhost:27017"))
    if err != nil {
        return err
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    err = client.Connect(ctx)
    if err != nil {
        return err
    }

    err = client.Ping(ctx, nil)
    if err != nil {
        return err
    }

    MI = MongoInstance{
        Client: client,
        DB:     client.Database(DATABASE),
    }

    return nil
}

func main() {
    if err := ConnectDB(); err != nil {
        log.Fatal(err)
    }

    r := gin.Default()
    // Routes will go here
    r.Run(":8080")
}
```

## 📚 Models and Collections

### Model Definition
```go
package models

import (
    "time"
    "go.mongodb.org/mongo-driver/bson/primitive"
)

type User struct {
    ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    Name      string            `bson:"name" json:"name" binding:"required"`
    Email     string            `bson:"email" json:"email" binding:"required,email"`
    Password  string            `bson:"password" json:"-" binding:"required"`
    CreatedAt time.Time         `bson:"created_at" json:"created_at"`
    UpdatedAt time.Time         `bson:"updated_at" json:"updated_at"`
}

type Post struct {
    ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    UserID    primitive.ObjectID `bson:"user_id" json:"user_id"`
    Title     string            `bson:"title" json:"title" binding:"required"`
    Content   string            `bson:"content" json:"content" binding:"required"`
    CreatedAt time.Time         `bson:"created_at" json:"created_at"`
    UpdatedAt time.Time         `bson:"updated_at" json:"updated_at"`
}
```

## 🎯 CRUD Operations

### Create Operation
```go
func CreateUser(c *gin.Context) {
    var user models.User
    if err := c.ShouldBindJSON(&user); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    user.ID = primitive.NewObjectID()
    user.CreatedAt = time.Now()
    user.UpdatedAt = time.Now()

    result, err := MI.DB.Collection("users").InsertOne(ctx, user)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(201, gin.H{
        "message": "User created successfully",
        "id":      result.InsertedID,
    })
}
```

### Read Operations
```go
// Get single user
func GetUser(c *gin.Context) {
    id := c.Param("id")
    objID, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        c.JSON(400, gin.H{"error": "Invalid ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    var user models.User
    err = MI.DB.Collection("users").FindOne(ctx, bson.M{"_id": objID}).Decode(&user)
    if err != nil {
        if err == mongo.ErrNoDocuments {
            c.JSON(404, gin.H{"error": "User not found"})
            return
        }
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(200, user)
}

// Get all users with pagination
func GetUsers(c *gin.Context) {
    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
    limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
    skip := (page - 1) * limit

    opts := options.Find().
        SetSkip(int64(skip)).
        SetLimit(int64(limit)).
        SetSort(bson.D{{Key: "created_at", Value: -1}})

    cursor, err := MI.DB.Collection("users").Find(ctx, bson.M{}, opts)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    defer cursor.Close(ctx)

    var users []models.User
    if err = cursor.All(ctx, &users); err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(200, users)
}
```

### Update Operation
```go
func UpdateUser(c *gin.Context) {
    id := c.Param("id")
    objID, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        c.JSON(400, gin.H{"error": "Invalid ID"})
        return
    }

    var updateUser models.User
    if err := c.ShouldBindJSON(&updateUser); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    updateUser.UpdatedAt = time.Now()

    update := bson.M{
        "$set": bson.M{
            "name":       updateUser.Name,
            "email":      updateUser.Email,
            "updated_at": updateUser.UpdatedAt,
        },
    }

    result, err := MI.DB.Collection("users").UpdateOne(
        ctx,
        bson.M{"_id": objID},
        update,
    )

    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    if result.MatchedCount == 0 {
        c.JSON(404, gin.H{"error": "User not found"})
        return
    }

    c.JSON(200, gin.H{"message": "User updated successfully"})
}
```

### Delete Operation
```go
func DeleteUser(c *gin.Context) {
    id := c.Param("id")
    objID, err := primitive.ObjectIDFromHex(id)
    if err != nil {
        c.JSON(400, gin.H{"error": "Invalid ID"})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    result, err := MI.DB.Collection("users").DeleteOne(ctx, bson.M{"_id": objID})
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    if result.DeletedCount == 0 {
        c.JSON(404, gin.H{"error": "User not found"})
        return
    }

    c.JSON(200, gin.H{"message": "User deleted successfully"})
}
```

## 🔍 Advanced Queries

### Aggregation Pipeline
```go
func GetUserStats(c *gin.Context) {
    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    pipeline := mongo.Pipeline{
        {{Key: "$group", Value: bson.D{
            {Key: "_id", Value: nil},
            {Key: "total", Value: bson.D{{Key: "$sum", Value: 1}}},
            {Key: "average_age", Value: bson.D{{Key: "$avg", Value: "$age"}}},
        }}},
    }

    cursor, err := MI.DB.Collection("users").Aggregate(ctx, pipeline)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    defer cursor.Close(ctx)

    var results []bson.M
    if err = cursor.All(ctx, &results); err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(200, results)
}
```

### Complex Queries
```go
func SearchUsers(c *gin.Context) {
    query := c.Query("q")
    
    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    filter := bson.M{
        "$or": []bson.M{
            {"name": bson.M{"$regex": query, "$options": "i"}},
            {"email": bson.M{"$regex": query, "$options": "i"}},
        },
    }

    opts := options.Find().
        SetSort(bson.D{{Key: "created_at", Value: -1}}).
        SetLimit(10)

    cursor, err := MI.DB.Collection("users").Find(ctx, filter, opts)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    defer cursor.Close(ctx)

    var users []models.User
    if err = cursor.All(ctx, &users); err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(200, users)
}
```

## 🔒 Repository Pattern

### Repository Interface
```go
type UserRepository interface {
    Create(ctx context.Context, user *models.User) error
    FindByID(ctx context.Context, id primitive.ObjectID) (*models.User, error)
    Update(ctx context.Context, user *models.User) error
    Delete(ctx context.Context, id primitive.ObjectID) error
    FindAll(ctx context.Context, page, limit int) ([]models.User, error)
}

type MongoUserRepository struct {
    db *mongo.Database
}

func NewMongoUserRepository(db *mongo.Database) UserRepository {
    return &MongoUserRepository{db: db}
}

func (r *MongoUserRepository) Create(ctx context.Context, user *models.User) error {
    user.ID = primitive.NewObjectID()
    user.CreatedAt = time.Now()
    user.UpdatedAt = time.Now()

    _, err := r.db.Collection("users").InsertOne(ctx, user)
    return err
}

// Implement other methods...
```

## 🔄 Transactions

### Transaction Example
```go
func CreateUserWithPosts(c *gin.Context) {
    var userData struct {
        User  models.User
        Posts []models.Post
    }

    if err := c.ShouldBindJSON(&userData); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
    defer cancel()

    session, err := MI.Client.StartSession()
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }
    defer session.EndSession(ctx)

    // Start transaction
    callback := func(sessionContext mongo.SessionContext) (interface{}, error) {
        // Insert user
        userData.User.ID = primitive.NewObjectID()
        userData.User.CreatedAt = time.Now()
        _, err := MI.DB.Collection("users").InsertOne(sessionContext, userData.User)
        if err != nil {
            return nil, err
        }

        // Insert posts
        for i := range userData.Posts {
            userData.Posts[i].ID = primitive.NewObjectID()
            userData.Posts[i].UserID = userData.User.ID
            userData.Posts[i].CreatedAt = time.Now()
        }

        _, err = MI.DB.Collection("posts").InsertMany(sessionContext, userData.Posts)
        if err != nil {
            return nil, err
        }

        return userData.User.ID, nil
    }

    result, err := session.WithTransaction(ctx, callback)
    if err != nil {
        c.JSON(500, gin.H{"error": err.Error()})
        return
    }

    c.JSON(201, gin.H{
        "message": "User and posts created successfully",
        "user_id": result,
    })
}
```

## 💡 Tips and Best Practices

1. **Use Context with Timeout**
   ```go
   // Always use context with timeout for database operations
   ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
   defer cancel()
   ```

2. **Proper Error Handling**
   ```go
   // Check for specific MongoDB errors
   if err == mongo.ErrNoDocuments {
       // Handle not found
   } else if writeErr, ok := err.(mongo.WriteException); ok {
       if writeErr.HasErrorCode(11000) {
           // Handle duplicate key error
       }
   }
   ```

3. **Indexes**
   ```go
   func createIndexes() error {
       ctx, cancel := context.WithTimeout(context.Background(), TIMEOUT)
       defer cancel()

       // Create email unique index
       _, err := MI.DB.Collection("users").Indexes().CreateOne(ctx,
           mongo.IndexModel{
               Keys: bson.D{{Key: "email", Value: 1}},
               Options: options.Index().SetUnique(true),
           },
       )
       return err
   }
   ```

4. **Use Projection**
   ```go
   // Only fetch required fields
   opts := options.FindOne().SetProjection(bson.M{
       "password": 0,
       "name": 1,
       "email": 1,
   })
   ```

Remember:
- Always use context with timeout
- Implement proper error handling
- Use indexes for better performance
- Follow repository pattern for clean code
- Use transactions when needed
- Properly handle MongoDB connections