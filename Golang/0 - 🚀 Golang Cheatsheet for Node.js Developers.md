
## 📌 Key Differences from Node.js
- Golang is statically typed (vs JavaScript's dynamic typing)
- Compilation vs interpretation
- No class-based OOP (structs and interfaces instead)
- Built-in concurrency with goroutines (vs async/await)
- No exceptions (error handling through return values)
- No undefined/null (use zero values instead)
- No implicit type conversion

## 🎯 Basic Syntax

### Variables and Types
```go
// Variable declaration
var name string = "John"
age := 25  // Type inference (only inside functions)

// Constants
const Pi = 3.14

// Basic types
var (
    intVar    int     = 42        // Platform dependent (int32 or int64)
    floatVar  float64 = 3.14      // Also float32
    boolVar   bool    = true      
    stringVar string  = "hello"   // Immutable strings (like JS)
    runeVar   rune    = 'A'       // Unicode character (int32)
    byteVar   byte    = 65        // uint8
)

// Zero values (no undefined!)
var (
    numZero   int     // 0
    strZero   string  // ""
    boolZero  bool    // false
    pointerZero *int  // nil
)
```

### Functions
```go
// Basic function
func add(x int, y int) int {
    return x + y
}

// Multiple return values (common for error handling)
func divide(x, y float64) (float64, error) {
    if y == 0 {
        return 0, errors.New("division by zero")
    }
    return x / y, nil
}

// Named return values
func split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return  // "naked" return
}

// Functions as values (like JS!)
var compute = func(x, y int) int {
    return x + y
}
```

### Control Flow
```go
// If statement (no parentheses needed!)
if x > 0 {
    // code
} else if x < 0 {
    // code
} else {
    // code
}

// With initialization statement
if value := getValue(); value > 0 {
    // value only exists in this scope
}

// Switch (no break needed!)
switch os := runtime.GOOS; os {
case "darwin":
    fmt.Println("macOS")
case "linux":
    fmt.Println("Linux")
default:
    fmt.Printf("%s\n", os)
}

// For loop (only loop type in Go!)
for i := 0; i < 10; i++ {
    // like C-style for loop
}

// For as while
for condition {
    // like while loop
}

// Infinite loop
for {
    // like while(true)
}

// Range (like JS for...of)
for index, value := range slice {
    // iterate over array/slice
}
for key, value := range map {
    // iterate over map
}
```

### Collections
```go
// Arrays (fixed length!)
var arr [5]int                    // [0,0,0,0,0]
arr2 := [3]string{"a", "b", "c"} // Initialize with values

// Slices (dynamic arrays, like JS arrays)
slice := []int{1, 2, 3}
slice = append(slice, 4)          // Add elements
slice2 := make([]int, 5)          // Create with length 5
len(slice)                        // Length
cap(slice)                        // Capacity

// Maps (like JS objects/Map)
map1 := make(map[string]int)
map2 := map[string]int{
    "apple":  5,
    "banana": 8,
}
delete(map1, "key")              // Delete key
value, exists := map1["key"]     // Check if key exists
```


A slice is an abstraction that uses an array under the covers.

- `cap` tells you the capacity of the underlying array (see [docs for cap()](https://pkg.go.dev/builtin#cap)).
- `len` tells you how many items are in the array (see [docs for len()](https://pkg.go.dev/builtin#len)).

The slice abstraction in Go is very nice since it will resize the underlying array for you, plus in Go arrays cannot be resized so slices are almost always used instead.

Example:

```go
s := make([]int, 0, 3)
for i := 0; i < 5; i++ {
    s = append(s, i)
    fmt.Printf("cap %v, len %v, %p\n", cap(s), len(s), s)
}
```

Will output something like this:

```go
cap 3, len 1, 0x1040e130
cap 3, len 2, 0x1040e130
cap 3, len 3, 0x1040e130
cap 6, len 4, 0x10432220
cap 6, len 5, 0x10432220
```

As you can see once the capacity is met, `append` will return a new slice with a larger capacity. On the 4th iteration you will notice a larger capacity and a new pointer address.

### Error Handling
```go
// Node.js vs Go error handling
// Node.js:
try {
    const result = riskyOperation();
} catch (err) {
    console.error(err);
}

// Go:
result, err := riskyOperation()
if err != nil {
    log.Fatal(err)
    return
}

// Multiple error checks
value1, err := operation1()
if err != nil {
    return err
}
value2, err := operation2(value1)
if err != nil {
    return err
}
```

## 🎁 Gotchas for Node.js Developers

1. **Package Scope**
   - No `var`, `let`, or `const` difference
   - Capitalized names are exported (public)
   - Lowercase names are package-private

2. **Error Handling**
   - No try/catch
   - Errors are return values
   - Multiple return values are common
   - Check for `nil` errors explicitly

3. **Concurrency**
   - Use goroutines instead of async/await
   - Channels for communication instead of Promises
   - Built-in race condition detection

4. **Types**
   - No type coercion
   - Strict type checking
   - No undefined (use zero values)
   - No classes (use structs and interfaces)

5. **Memory Management**
   - No garbage collection configuration needed
   - Stack vs heap allocation is automatic
   - No reference vs primitive types distinction

6. **Formatting**
   - `gofmt` tool enforces standard formatting
   - No semicolons (inserted automatically)
   - Unused imports/variables are compile errors

## 🚨 Common Mistakes to Avoid

1. Using `nil` without pointer/interface/slice/map/channel/function types
2. Ignoring returned errors
3. Using pointer receivers unnecessarily
4. Not using `gofmt`
5. Treating slices like JavaScript arrays (they're different!)
6. Not using the blank identifier (_) when needed
7. Not understanding when to use pointers vs values

Remember:
- Go is all about simplicity and explicitness
- Standard library is your best friend
- Code organization is different (packages vs modules)
- Error handling is part of the flow, not exceptional