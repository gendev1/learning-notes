
## 🏗️ Creational Patterns

### 1. Singleton
```go
type Database struct {
    connection string
}

var (
    instance *Database
    once     sync.Once
)

func GetDatabase() *Database {
    once.Do(func() {
        instance = &Database{
            connection: "mongodb://localhost:27017",
        }
    })
    return instance
}
```

### 2. Factory Method
```go
type Payment interface {
    Pay(amount float64) error
}

type CreditCard struct{}
type PayPal struct{}

func (c *CreditCard) Pay(amount float64) error {
    // Implementation
    return nil
}

func (p *PayPal) Pay(amount float64) error {
    // Implementation
    return nil
}

func NewPayment(method string) Payment {
    switch method {
    case "creditcard":
        return &CreditCard{}
    case "paypal":
        return &PayPal{}
    default:
        return nil
    }
}
```

### 3. Builder
```go
type Server struct {
    host    string
    port    int
    timeout time.Duration
    maxConn int
}

type ServerBuilder struct {
    server *Server
}

func NewServerBuilder() *ServerBuilder {
    return &ServerBuilder{server: &Server{}}
}

func (b *ServerBuilder) Host(host string) *ServerBuilder {
    b.server.host = host
    return b
}

func (b *ServerBuilder) Port(port int) *ServerBuilder {
    b.server.port = port
    return b
}

func (b *ServerBuilder) Build() *Server {
    return b.server
}

// Usage
server := NewServerBuilder().
    Host("localhost").
    Port(8080).
    Build()
```

## 🔄 Behavioral Patterns

### 1. Observer
```go
type Observer interface {
    Update(data interface{})
}

type Subject struct {
    observers []Observer
    data      interface{}
}

func (s *Subject) Attach(observer Observer) {
    s.observers = append(s.observers, observer)
}

func (s *Subject) Notify() {
    for _, observer := range s.observers {
        observer.Update(s.data)
    }
}

// Example implementation
type EmailNotifier struct {
    email string
}

func (e *EmailNotifier) Update(data interface{}) {
    // Send email notification
}
```

### 2. Strategy
```go
type SortStrategy interface {
    Sort([]int) []int
}

type QuickSort struct{}
type BubbleSort struct{}

func (q *QuickSort) Sort(data []int) []int {
    // QuickSort implementation
    return data
}

func (b *BubbleSort) Sort(data []int) []int {
    // BubbleSort implementation
    return data
}

type Sorter struct {
    strategy SortStrategy
}

func (s *Sorter) SetStrategy(strategy SortStrategy) {
    s.strategy = strategy
}

func (s *Sorter) Sort(data []int) []int {
    return s.strategy.Sort(data)
}
```

### 3. Chain of Responsibility
```go
type Handler interface {
    Handle(request string) string
    SetNext(handler Handler) Handler
}

type BaseHandler struct {
    next Handler
}

func (h *BaseHandler) SetNext(handler Handler) Handler {
    h.next = handler
    return handler
}

type AuthHandler struct {
    BaseHandler
}

func (h *AuthHandler) Handle(request string) string {
    if request == "auth" {
        return "Authenticated"
    }
    if h.next != nil {
        return h.next.Handle(request)
    }
    return ""
}

// Usage
auth := &AuthHandler{}
logging := &LoggingHandler{}
auth.SetNext(logging)
```

## 🏢 Structural Patterns

### 1. Adapter
```go
type LegacyPrinter interface {
    Print(s string) string
}

type ModernPrinter interface {
    PrintModern(s string) string
}

type ModernPrinterImpl struct{}

func (p *ModernPrinterImpl) PrintModern(s string) string {
    return "Modern: " + s
}

type PrinterAdapter struct {
    modernPrinter ModernPrinter
}

func (p *PrinterAdapter) Print(s string) string {
    return p.modernPrinter.PrintModern(s)
}
```

### 2. Decorator
```go
type Component interface {
    Operation() string
}

type ConcreteComponent struct{}

func (c *ConcreteComponent) Operation() string {
    return "ConcreteComponent"
}

type Decorator struct {
    component Component
}

func (d *Decorator) Operation() string {
    if d.component != nil {
        return d.component.Operation()
    }
    return ""
}

type ConcreteDecoratorA struct {
    Decorator
}

func (d *ConcreteDecoratorA) Operation() string {
    return "ConcreteDecoratorA(" + d.Decorator.Operation() + ")"
}
```

### 3. Proxy
```go
type Server interface {
    HandleRequest(string) (string, error)
}

type RealServer struct{}

func (s *RealServer) HandleRequest(request string) (string, error) {
    return "Handled: " + request, nil
}

type ProxyServer struct {
    realServer *RealServer
    cache      map[string]string
}

func (p *ProxyServer) HandleRequest(request string) (string, error) {
    if response, exists := p.cache[request]; exists {
        return response, nil
    }
    
    response, err := p.realServer.HandleRequest(request)
    if err == nil {
        p.cache[request] = response
    }
    return response, err
}
```

## 🔧 Concurrency Patterns

### 1. Worker Pool
```go
func worker(id int, jobs <-chan int, results chan<- int) {
    for j := range jobs {
        results <- j * 2
    }
}

func WorkerPool(numWorkers int) {
    jobs := make(chan int, 100)
    results := make(chan int, 100)

    // Start workers
    for w := 1; w <= numWorkers; w++ {
        go worker(w, jobs, results)
    }

    // Send jobs
    for j := 1; j <= 100; j++ {
        jobs <- j
    }
    close(jobs)

    // Collect results
    for a := 1; a <= 100; a++ {
        <-results
    }
}
```

### 2. Pipeline
```go
func generator(nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        for _, n := range nums {
            out <- n
        }
        close(out)
    }()
    return out
}

func square(in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        for n := range in {
            out <- n * n
        }
        close(out)
    }()
    return out
}

// Usage
nums := generator(1, 2, 3, 4)
squares := square(nums)
```

### 3. Fan-Out, Fan-In
```go
func fanOut(ch <-chan int, n int) []<-chan int {
    channels := make([]<-chan int, n)
    for i := 0; i < n; i++ {
        channels[i] = processChannel(ch)
    }
    return channels
}

func fanIn(channels ...<-chan int) <-chan int {
    var wg sync.WaitGroup
    multiplexedStream := make(chan int)

    multiplex := func(c <-chan int) {
        defer wg.Done()
        for i := range c {
            multiplexedStream <- i
        }
    }

    wg.Add(len(channels))
    for _, c := range channels {
        go multiplex(c)
    }

    go func() {
        wg.Wait()
        close(multiplexedStream)
    }()

    return multiplexedStream
}
```

## 💡 Functional Patterns

### 1. Options Pattern
```go
type Server struct {
    host    string
    port    int
    timeout time.Duration
}

type ServerOption func(*Server)

func WithHost(host string) ServerOption {
    return func(s *Server) {
        s.host = host
    }
}

func WithPort(port int) ServerOption {
    return func(s *Server) {
        s.port = port
    }
}

func NewServer(opts ...ServerOption) *Server {
    server := &Server{
        host: "localhost",  // default value
        port: 8080,        // default value
    }
    
    for _, opt := range opts {
        opt(server)
    }
    
    return server
}

// Usage
server := NewServer(
    WithHost("example.com"),
    WithPort(9000),
)
```

### 2. Middleware Pattern
```go
type Middleware func(http.HandlerFunc) http.HandlerFunc

func Logger() Middleware {
    return func(next http.HandlerFunc) http.HandlerFunc {
        return func(w http.ResponseWriter, r *http.Request) {
            log.Printf("Request: %s %s", r.Method, r.URL.Path)
            next(w, r)
        }
    }
}

func Authentication() Middleware {
    return func(next http.HandlerFunc) http.HandlerFunc {
        return func(w http.ResponseWriter, r *http.Request) {
            // Check auth
            next(w, r)
        }
    }
}

// Usage
func Chain(f http.HandlerFunc, middlewares ...Middleware) http.HandlerFunc {
    for _, m := range middlewares {
        f = m(f)
    }
    return f
}
```

## 🎯 Tips for Node.js Developers

1. **Pattern Selection**
   - Go favors simpler patterns
   - Composition over inheritance
   - Interface-based design
   - Concurrency patterns are unique to Go

2. **Key Differences**
   - No class-based inheritance
   - No method overriding
   - Interfaces are implicit
   - Goroutines vs async/await

3. **Common Patterns from Node.js**
   ```go
   // Node.js Middleware
   app.use(middleware)
   
   // Go Middleware
   http.Handle("/", Chain(handler, 
       Logger(),
       Authentication(),
   ))
   ```

Remember:
- Keep it simple
- Use interfaces for flexibility
- Favor composition
- Consider concurrency
- Use built-in patterns when possible