
## 🚀 Goroutines 
Think of goroutines as lightweight threads (like async functions in Node.js, but better!)

### Basic Syntax
```go
// Starting a goroutine
go functionName()
go func() {
    // anonymous function
}()
```

### From Node.js to Go
```go
// Node.js async/await:
async function fetchData() {
    const result = await fetch(url);
    return result;
}

// Go equivalent:
func fetchData() {
    go func() {
        result := fetch(url)
        // handle result
    }()
}
```

### Important Goroutine Patterns

1. **Wait Groups** (Like Promise.all)
```go
var wg sync.WaitGroup

func main() {
    // Add 3 to wait group counter
    wg.Add(3)
    
    go func() {
        defer wg.Done() // Decrements counter
        // do something
    }()
    
    go func() {
        defer wg.Done()
        // do something else
    }()
    
    go func() {
        defer wg.Done()
        // do another thing
    }()
    
    wg.Wait() // Wait for all goroutines to finish
}
```

2. **Worker Pools** (Like Worker Threads in Node.js)
```go
func worker(id int, jobs <-chan int, results chan<- int) {
    for j := range jobs {
        fmt.Printf("worker %d processing job %d\n", id, j)
        time.Sleep(time.Second)
        results <- j * 2
    }
}

func main() {
    jobs := make(chan int, 100)
    results := make(chan int, 100)

    // Start 3 workers
    for w := 1; w <= 3; w++ {
        go worker(w, jobs, results)
    }

    // Send 9 jobs
    for j := 1; j <= 9; j++ {
        jobs <- j
    }
    close(jobs)

    // Collect results
    for a := 1; a <= 9; a++ {
        <-results
    }
}
```

## 📬 Channels
Channels are typed conduits for communication between goroutines (like a type-safe EventEmitter)

### Channel Basics
```go
// Create channels
ch := make(chan int)        // Unbuffered channel
ch := make(chan int, 100)   // Buffered channel with capacity 100

// Send data
ch <- 42                    // Send value to channel

// Receive data
value := <-ch              // Receive from channel
value, ok := <-ch          // Check if channel is closed

// Close channel
close(ch)
```

### Channel Patterns

1. **Generator Pattern** (Like Async Generators in Node.js)
```go
func fibonacci(n int) chan int {
    ch := make(chan int)
    go func() {
        a, b := 0, 1
        for i := 0; i < n; i++ {
            ch <- a
            a, b = b, a+b
        }
        close(ch)
    }()
    return ch
}

// Usage
for num := range fibonacci(10) {
    fmt.Println(num)
}
```

2. **Fan-Out, Fan-In Pattern**
```go
func fanOut(ch <-chan int, n int) []<-chan int {
    channels := make([]<-chan int, n)
    for i := 0; i < n; i++ {
        channels[i] = worker(ch)
    }
    return channels
}

func fanIn(channels ...<-chan int) <-chan int {
    var wg sync.WaitGroup
    merged := make(chan int)

    output := func(c <-chan int) {
        for n := range c {
            merged <- n
        }
        wg.Done()
    }

    wg.Add(len(channels))
    for _, c := range channels {
        go output(c)
    }

    go func() {
        wg.Wait()
        close(merged)
    }()

    return merged
}
```

1. **Select Pattern** (Like Promise.race)
```go
select {
case msg1 := <-ch1:
    fmt.Println("Received from ch1:", msg1)
case msg2 := <-ch2:
    fmt.Println("Received from ch2:", msg2)
case ch3 <- "message":
    fmt.Println("Sent to ch3")
case <-time.After(time.Second):
    fmt.Println("Timeout")
default:
    fmt.Println("No channel ready")
}
```

## 🎯 Best Practices

2. **Channel Ownership**
```go
// Producer owns the channel
func producer() <-chan int {
    ch := make(chan int)
    go func() {
        defer close(ch)
        for i := 0; i < 5; i++ {
            ch <- i
        }
    }()
    return ch
}

// Consumer receives read-only channel
func consumer(ch <-chan int) {
    for num := range ch {
        fmt.Println(num)
    }
}
```

3. **Context for Cancellation**
```go
func worker(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        default:
            // Do work
        }
    }
}

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    go worker(ctx)
    // Worker will automatically stop after 5 seconds
}
```

## 🚨 Common Gotchas

4. **Deadlocks**
```go
// DEADLOCK: Unbuffered channel needs receiver
ch := make(chan int)
ch <- 1        // Blocks forever

// FIX: Use goroutine or buffered channel
go func() {
    ch <- 1
}()
// or
ch := make(chan int, 1)
```

5. **Goroutine Leaks**
```go
// LEAK: Goroutine never exits
go func() {
    ch := make(chan int)
    // Channel never receives, goroutine stays alive
}()

// FIX: Always ensure channels can be closed
ch := make(chan int)
go func() {
    defer close(ch)
    // Work
}()
```

6. **Race Conditions**
```go
// RACE: Multiple goroutines accessing shared variable
counter := 0
go func() {
    counter++
}()

// FIX: Use mutex or channels
var mutex sync.Mutex
mutex.Lock()
counter++
mutex.Unlock()
```

## 💡 Tips for Node.js Developers

7. Goroutines are much lighter than Node.js workers
8. Prefer channels over shared memory communication
9. Use `go run -race` to detect race conditions
10. Channels are typed and safer than EventEmitter
11. Context package replaces many Promise timeout patterns
12. WaitGroups are similar to Promise.all but more explicit
13. Select is like Promise.race but more powerful

Remember:
- Don't create goroutines without a way to stop them
- Always handle channel closure
- Use buffered channels when you know the capacity
- Let one goroutine own each channel
- Use context for cancellation and timeouts