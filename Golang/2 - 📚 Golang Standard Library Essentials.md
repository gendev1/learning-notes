

## 🔄 fmt
Printf and formatting (like console.log with superpowers)

```go
// Printing
fmt.Println("Hello")               // Print with newline
fmt.Printf("Number: %d\n", 42)     // Formatted print
fmt.Sprintf("Hello %s", "World")   // Return formatted string

// Formatting verbs
fmt.Printf("%v", anyValue)         // Default format
fmt.Printf("%+v", struct)          // Struct with field names
fmt.Printf("%#v", value)           // Go syntax format
fmt.Printf("%T", value)            // Type of value
fmt.Printf("%t", bool)             // True or false
fmt.Printf("%d", integer)          // Base 10
fmt.Printf("%f", float)            // Float
fmt.Printf("%s", string)           // String
fmt.Printf("%p", pointer)          // Pointer address
```

## 📂 io
I/O interfaces and utilities (like Node.js streams)

```go
// Common interfaces
type Reader interface {
    Read(p []byte) (n int, err error)
}
type Writer interface {
    Write(p []byte) (n int, err error)
}

// Useful utilities
io.Copy(dst Writer, src Reader)    // Copy from reader to writer
io.ReadAll(r Reader)              // Read everything into []byte
io.WriteString(w Writer, s string) // Write string to writer
io.MultiWriter(writers...)        // Write to multiple writers
```

## 🌐 net/http
HTTP server and client (like Express.js + fetch)

```go
// Simple server
http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "Hello, %s!", r.URL.Path[1:])
})
http.ListenAndServe(":8080", nil)

// Server with mux (router)
mux := http.NewServeMux()
mux.HandleFunc("/api/", apiHandler)
mux.HandleFunc("/static/", staticHandler)
server := &http.Server{
    Addr:    ":8080",
    Handler: mux,
}
server.ListenAndServe()

// HTTP client
client := &http.Client{}
resp, err := client.Get("https://api.example.com")
if err != nil {
    log.Fatal(err)
}
defer resp.Body.Close()

// POST request
resp, err := http.Post("https://api.example.com",
    "application/json",
    strings.NewReader(`{"name":"John"}`))

// Custom request
req, err := http.NewRequest("POST", "https://api.example.com", body)
req.Header.Set("Content-Type", "application/json")
resp, err := client.Do(req)
```

## 📄 encoding/json
JSON handling (like JSON.parse/stringify)

```go
// Marshal (stringify)
type Person struct {
    Name    string `json:"name"`
    Age     int    `json:"age"`
    Private string `json:"-"`        // Skip this field
}

person := Person{Name: "John", Age: 30}
data, err := json.Marshal(person)

// Unmarshal (parse)
var p Person
err := json.Unmarshal(data, &p)

// Working with unknown JSON
var data map[string]interface{}
err := json.Unmarshal(rawJSON, &data)

// JSON encoder/decoder (streaming)
enc := json.NewEncoder(w)
enc.Encode(data)

dec := json.NewDecoder(r)
err := dec.Decode(&data)
```

## ⏱️ time
Time handling (like Date in JS)

```go
// Current time
now := time.Now()
fmt.Println(now.Year(), now.Month(), now.Day())

// Duration
duration := 5 * time.Second
time.Sleep(duration)

// Parsing time
t, err := time.Parse("2006-01-02", "2023-06-15")
t, err := time.Parse(time.RFC3339, "2023-06-15T14:00:00Z")

// Formatting time
fmt.Println(now.Format("2006-01-02 15:04:05"))
fmt.Println(now.Format(time.RFC3339))

// Add/Sub durations
future := now.Add(24 * time.Hour)
past := now.Add(-24 * time.Hour)
diff := future.Sub(past)

// Timers and tickers
timer := time.NewTimer(2 * time.Second)
<-timer.C    // Wait for timer

ticker := time.NewTicker(1 * time.Second)
for t := range ticker.C {
    fmt.Println("Tick at", t)
}
```

## 📁 os
Operating system functionality (like Node.js fs)

```go
// File operations
file, err := os.Open("file.txt")
file, err := os.Create("file.txt")
defer file.Close()

// Read entire file
data, err := os.ReadFile("file.txt")

// Write entire file
err := os.WriteFile("file.txt", data, 0644)

// File info
info, err := os.Stat("file.txt")
fmt.Println(info.Size(), info.ModTime())

// Directory operations
err := os.MkdirAll("path/to/dir", 0755)
entries, err := os.ReadDir(".")

// Environment variables
os.Setenv("KEY", "VALUE")
value := os.Getenv("KEY")
```

## 🔒 crypto
Cryptographic functions (like Node.js crypto)

```go
// Hashing
h := sha256.New()
h.Write([]byte("hello world"))
hash := h.Sum(nil)

// Random numbers
token := make([]byte, 16)
rand.Read(token)

// BCrypt (for passwords)
hash, err := bcrypt.GenerateFromPassword([]byte("password"), bcrypt.DefaultCost)
err := bcrypt.CompareHashAndPassword(hash, []byte("password"))
```

## 📝 bufio
Buffered I/O (like Node.js readline)

```go
// Buffered reader
reader := bufio.NewReader(os.Stdin)
line, err := reader.ReadString('\n')

// Scanner
scanner := bufio.NewScanner(file)
for scanner.Scan() {
    fmt.Println(scanner.Text())
}

// Buffered writer
writer := bufio.NewWriter(file)
writer.WriteString("hello")
writer.Flush()
```

## 🧵 sync
Synchronization primitives

```go
// Mutex
var mu sync.Mutex
mu.Lock()
// critical section
mu.Unlock()

// RWMutex (multiple readers, single writer)
var rwmu sync.RWMutex
rwmu.RLock()  // Read lock
rwmu.RUnlock()

// Once
var once sync.Once
once.Do(func() {
    // run only once
})

// Pool
pool := sync.Pool{
    New: func() interface{} {
        return make([]byte, 1024)
    },
}
buf := pool.Get().([]byte)
defer pool.Put(buf)
```

## 🎯 context
Context management (like request context in Express)

```go
// Creating context
ctx := context.Background()
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()

// With value
ctx = context.WithValue(ctx, "key", "value")
value := ctx.Value("key").(string)

// With deadline
ctx, cancel = context.WithDeadline(ctx, time.Now().Add(time.Hour))

// Using with HTTP
req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
```

## 💡 Tips

1. **Standard Library Over Third Party**
   - Go's standard library is extensive and well-tested
   - Often, you don't need external packages
   - Look in standard library first before using third-party

2. **Common Combinations**
   ```go
   // HTTP + JSON
   func handler(w http.ResponseWriter, r *http.Request) {
       var data struct{ Name string }
       json.NewDecoder(r.Body).Decode(&data)
       json.NewEncoder(w).Encode(response)
   }

   // Files + Bufio
   file, _ := os.Open("large.txt")
   scanner := bufio.NewScanner(file)
   for scanner.Scan() {
       processLine(scanner.Text())
   }
   ```

3. **Interface Satisfaction**
   - Many standard library interfaces are small and composable
   - io.Reader and io.Writer are everywhere
   - Easy to implement custom types that satisfy these interfaces

Remember:
- Standard library is your friend
- Documentation at pkg.go.dev is excellent
- Interfaces make components pluggable
- Built-in testing support for all packages