# Building a Kafka Consumer for Protocol Buffers in Golang

This tutorial will guide you through the process of creating a Kafka consumer for a microservice that processes Protocol Buffer messages. We'll focus on:

1. Setting up mTLS certificates for Kafka
2. Running consumers in goroutines
3. Using channels for communication
4. Processing messages within an HTTP microservice
5. Converting proto files to Go code

## Project Structure

Let's start with a clean project structure:

```
myservice/
├── cmd/
│   └── server/
│       └── main.go
├── internal/
│   ├── config/
│   │   └── config.go
│   ├── kafka/
│   │   ├── consumer.go
│   │   └── message_processor.go
│   ├── models/
│   │   └── models.go
│   ├── proto/
│   │   └── generated/ (auto-generated .pb.go files)
│   └── handlers/
│       └── handlers.go
├── proto/
│   └── *.proto (original proto files)
├── scripts/
│   └── generate_protos.sh
├── go.mod
├── go.sum
└── audit_topic_mapper.json
```

## Step 1: Setting Up the Project

First, initialize your Go module and install dependencies:

```bash
mkdir -p myservice
cd myservice
go mod init github.com/yourusername/myservice
go get -u github.com/confluentinc/confluent-kafka-go/kafka
go get -u google.golang.org/protobuf/proto
go get -u google.golang.org/protobuf/cmd/protoc-gen-go
```

## Step 2: Creating a Script to Generate Protocol Buffer Code

First, let's create a script to convert `.proto` files to `.pb.go` files.

Create `scripts/generate_protos.sh`:

```bash
#!/bin/bash

# Directory containing proto files
PROTO_DIR="proto"
# Directory for generated Go files
OUTPUT_DIR="internal/proto/generated"

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR

# Find all proto files and compile them
for proto_file in $(find $PROTO_DIR -name "*.proto"); do
  protoc \
    --proto_path=$PROTO_DIR \
    --go_out=$OUTPUT_DIR \
    --go_opt=paths=source_relative \
    $proto_file
  
  echo "Compiled: $proto_file"
done

echo "Protocol buffer code generation complete!"
```

Make the script executable:

```bash
chmod +x scripts/generate_protos.sh
```

## Step 3: Setting Up Configuration

Create `internal/config/config.go` to handle your application configuration:

```go
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// TopicMapping represents a mapping between a Kafka topic and message types
type TopicMapping struct {
	Topic      string   `json:"topic"`
	MessageIDs []string `json:"message_ids"`
}

// Config holds all configuration for the application
type Config struct {
	// Kafka configuration
	KafkaBootstrapServers string
	KafkaGroupID          string
	KafkaCertPath         string
	KafkaKeyPath          string
	KafkaCaPath           string
	
	// HTTP server config
	ServerPort            string
	
	// Topic mappings
	TopicMappings         []TopicMapping
}

// LoadConfig loads the configuration from environment variables and files
func LoadConfig() (*Config, error) {
	cfg := &Config{
		KafkaBootstrapServers: getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
		KafkaGroupID:          getEnv("KAFKA_GROUP_ID", "myservice-consumer"),
		KafkaCertPath:         getEnv("KAFKA_CERT_PATH", "./certs/client.crt"),
		KafkaKeyPath:          getEnv("KAFKA_KEY_PATH", "./certs/client.key"),
		KafkaCaPath:           getEnv("KAFKA_CA_PATH", "./certs/ca.crt"),
		ServerPort:            getEnv("SERVER_PORT", "8080"),
	}
	
	// Load topic mappings from JSON file
	err := cfg.loadTopicMappings(getEnv("TOPIC_MAPPER_PATH", "./audit_topic_mapper.json"))
	if err != nil {
		return nil, fmt.Errorf("failed to load topic mappings: %w", err)
	}
	
	return cfg, nil
}

// loadTopicMappings loads the topic to message mappings from the JSON file
func (c *Config) loadTopicMappings(filePath string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}
	
	return json.Unmarshal(data, &c.TopicMappings)
}

// getEnv gets an environment variable or returns a default value
func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// GetTopicList returns a list of all topics to subscribe to
func (c *Config) GetTopicList() []string {
	topics := make([]string, 0, len(c.TopicMappings))
	for _, mapping := range c.TopicMappings {
		topics = append(topics, mapping.Topic)
	}
	return topics
}

// GetMessageIDsForTopic returns the message IDs for a specific topic
func (c *Config) GetMessageIDsForTopic(topic string) []string {
	for _, mapping := range c.TopicMappings {
		if mapping.Topic == topic {
			return mapping.MessageIDs
		}
	}
	return nil
}
```

## Step 4: Creating Kafka Consumer with mTLS Support

Create `internal/kafka/consumer.go`:

```go
package kafka

import (
	"context"
	"fmt"
	"log"
	"sync"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/yourusername/myservice/internal/config"
)

// MessageHandler is a function that processes a Kafka message
type MessageHandler func(topic string, data []byte) error

// Consumer manages Kafka consumer instances
type Consumer struct {
	config         *config.Config
	messageHandler MessageHandler
	consumers      []*kafka.Consumer
	wg             sync.WaitGroup
}

// NewConsumer creates a new Kafka consumer manager
func NewConsumer(cfg *config.Config, handler MessageHandler) *Consumer {
	return &Consumer{
		config:         cfg,
		messageHandler: handler,
	}
}

// Start initializes and starts all Kafka consumers
func (c *Consumer) Start(ctx context.Context) error {
	topics := c.config.GetTopicList()
	
	for _, topic := range topics {
		consumer, err := c.createConsumer()
		if err != nil {
			return fmt.Errorf("failed to create consumer for topic %s: %w", topic, err)
		}
		
		err = consumer.Subscribe(topic, nil)
		if err != nil {
			return fmt.Errorf("failed to subscribe to topic %s: %w", topic, err)
		}
		
		c.consumers = append(c.consumers, consumer)
		
		// Start consumer in a goroutine
		c.wg.Add(1)
		go c.consumeMessages(ctx, consumer, topic)
	}
	
	return nil
}

// Stop gracefully stops all consumers
func (c *Consumer) Stop() {
	for _, consumer := range c.consumers {
		consumer.Close()
	}
	c.wg.Wait()
}

// createConsumer creates a new Kafka consumer with mTLS configuration
func (c *Consumer) createConsumer() (*kafka.Consumer, error) {
	config := &kafka.ConfigMap{
		"bootstrap.servers":        c.config.KafkaBootstrapServers,
		"group.id":                 c.config.KafkaGroupID,
		"auto.offset.reset":        "earliest",
		"enable.auto.commit":       true,
		"security.protocol":        "ssl",
		"ssl.certificate.location": c.config.KafkaCertPath,
		"ssl.key.location":         c.config.KafkaKeyPath,
		"ssl.ca.location":          c.config.KafkaCaPath,
	}
	
	return kafka.NewConsumer(config)
}

// consumeMessages consumes messages from a topic
func (c *Consumer) consumeMessages(ctx context.Context, consumer *kafka.Consumer, topic string) {
	defer c.wg.Done()
	
	for {
		select {
		case <-ctx.Done():
			log.Printf("Stopping consumer for topic: %s", topic)
			return
		default:
			msg, err := consumer.ReadMessage(-1)
			if err != nil {
				// Check if context is canceled before logging the error
				select {
				case <-ctx.Done():
					return
				default:
					log.Printf("Error reading message from topic %s: %v", topic, err)
					continue
				}
			}
			
			// Process the message
			err = c.messageHandler(topic, msg.Value)
			if err != nil {
				log.Printf("Error processing message from topic %s: %v", topic, err)
			}
		}
	}
}
```

## Step 5: Creating a Message Processor

Create `internal/kafka/message_processor.go`:

```go
package kafka

import (
	"errors"
	"fmt"
	"log"

	"google.golang.org/protobuf/proto"
	"github.com/yourusername/myservice/internal/config"
	"github.com/yourusername/myservice/internal/proto/generated"
)

// Processor handles processing of Kafka messages
type Processor struct {
	config *config.Config
	// You can add more dependencies here like a database connection
}

// NewProcessor creates a new message processor
func NewProcessor(cfg *config.Config) *Processor {
	return &Processor{
		config: cfg,
	}
}

// ProcessMessage processes a Kafka message based on the topic
func (p *Processor) ProcessMessage(topic string, data []byte) error {
	// Get message IDs for this topic
	messageIDs := p.config.GetMessageIDsForTopic(topic)
	if len(messageIDs) == 0 {
		return fmt.Errorf("no message IDs configured for topic: %s", topic)
	}
	
	// For simplicity, we're assuming each topic has one message type in this tutorial
	// In a real application, you might need to determine the message type from metadata
	messageID := messageIDs[0]
	
	// Process based on message ID
	switch messageID {
	case "YourMessageType":
		return p.processYourMessageType(data)
	// Add more cases for different message types
	default:
		return fmt.Errorf("unknown message ID: %s", messageID)
	}
}

// processYourMessageType processes your specific message type
func (p *Processor) processYourMessageType(data []byte) error {
	// Unmarshal the protocol buffer message
	// Replace YourMessageType with your actual generated message type
	var message generated.YourMessageType
	if err := proto.Unmarshal(data, &message); err != nil {
		return fmt.Errorf("failed to unmarshal message: %w", err)
	}
	
	// Process the message (this is where you'd implement your business logic)
	log.Printf("Processed message: %v", message)
	
	return nil
}

// GetMessageHandler returns a function that can be used as a message handler
func (p *Processor) GetMessageHandler() MessageHandler {
	return p.ProcessMessage
}
```

## Step 6: Setting Up HTTP Handlers

Create `internal/handlers/handlers.go`:

```go
package handlers

import (
	"net/http"

	"github.com/yourusername/myservice/internal/config"
	"github.com/yourusername/myservice/internal/kafka"
)

// Handler manages HTTP handlers
type Handler struct {
	config    *config.Config
	processor *kafka.Processor
}

// NewHandler creates a new HTTP handler
func NewHandler(cfg *config.Config, processor *kafka.Processor) *Handler {
	return &Handler{
		config:    cfg,
		processor: processor,
	}
}

// RegisterRoutes registers all HTTP routes
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("/health", h.healthCheck)
	// Add more routes as needed
}

// healthCheck is a simple health check endpoint
func (h *Handler) healthCheck(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}
```

## Step 7: Creating the Main Application

Create `cmd/server/main.go`:

```go
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/yourusername/myservice/internal/config"
	"github.com/yourusername/myservice/internal/handlers"
	"github.com/yourusername/myservice/internal/kafka"
)

func main() {
	log.Println("Starting service...")

	// Load configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Create a context that can be canceled
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Set up message processor
	processor := kafka.NewProcessor(cfg)

	// Set up Kafka consumer
	consumer := kafka.NewConsumer(cfg, processor.GetMessageHandler())
	err = consumer.Start(ctx)
	if err != nil {
		log.Fatalf("Failed to start Kafka consumer: %v", err)
	}
	defer consumer.Stop()

	// Set up HTTP server
	handler := handlers.NewHandler(cfg, processor)
	mux := http.NewServeMux()
	handler.RegisterRoutes(mux)
	
	server := &http.Server{
		Addr:    ":" + cfg.ServerPort,
		Handler: mux,
	}

	// Start HTTP server in a goroutine
	go func() {
		log.Printf("Starting HTTP server on port %s", cfg.ServerPort)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start HTTP server: %v", err)
		}
	}()

	// Wait for termination signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan
	
	log.Println("Received termination signal, shutting down...")
	
	// Graceful shutdown
	gracefulCtx, gracefulCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer gracefulCancel()
	
	if err := server.Shutdown(gracefulCtx); err != nil {
		log.Printf("HTTP server shutdown error: %v", err)
	}
	
	// Cancel the Kafka consumer context
	cancel()
	
	log.Println("Service stopped")
}
```

## Step 8: Example Implementation for a Specific Message Type

To make this more concrete, let's assume you have a proto file for an audit message. Here's how you might implement that:

1. First, create a sample proto file in `proto/audit.proto`:

```protobuf
syntax = "proto3";
package audit;

option go_package = "github.com/yourusername/myservice/internal/proto/generated";

message AuditEvent {
  string event_id = 1;
  string user_id = 2;
  string action = 3;
  string resource = 4;
  int64 timestamp = 5;
  map<string, string> metadata = 6;
}
```

2. Then run your script to generate Go code:

```bash
./scripts/generate_protos.sh
```

3. Update the message processor to handle the audit event:

```go
// In internal/kafka/message_processor.go

// ProcessMessage processes a Kafka message based on the topic
func (p *Processor) ProcessMessage(topic string, data []byte) error {
	// Get message IDs for this topic
	messageIDs := p.config.GetMessageIDsForTopic(topic)
	if len(messageIDs) == 0 {
		return fmt.Errorf("no message IDs configured for topic: %s", topic)
	}
	
	// For simplicity, we're assuming each topic has one message type in this tutorial
	messageID := messageIDs[0]
	
	// Process based on message ID
	switch messageID {
	case "AuditEvent":
		return p.processAuditEvent(data)
	// Add more cases for different message types
	default:
		return fmt.Errorf("unknown message ID: %s", messageID)
	}
}

// processAuditEvent processes audit events
func (p *Processor) processAuditEvent(data []byte) error {
	var event generated.AuditEvent
	if err := proto.Unmarshal(data, &event); err != nil {
		return fmt.Errorf("failed to unmarshal audit event: %w", err)
	}
	
	// Process the audit event
	log.Printf("Audit event received: ID=%s, User=%s, Action=%s, Resource=%s",
		event.EventId, event.UserId, event.Action, event.Resource)
	
	// Here you would typically store the event in a database or take some other action
	
	return nil
}
```

4. Create a sample `audit_topic_mapper.json`:

```json
[
  {
    "topic": "audit-events",
    "message_ids": ["AuditEvent"]
  }
]
```

## Usage Example

With this setup, you can start your service with:

```bash
# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS="kafka1:9092,kafka2:9092"
export KAFKA_GROUP_ID="myservice-consumers"
export KAFKA_CERT_PATH="./certs/client.crt"
export KAFKA_KEY_PATH="./certs/client.key"
export KAFKA_CA_PATH="./certs/ca.crt"
export TOPIC_MAPPER_PATH="./audit_topic_mapper.json"
export SERVER_PORT="8080"

# Run the service
go run cmd/server/main.go
```

## Conclusion

This tutorial has walked you through creating a clean, well-structured Kafka consumer for Protocol Buffer messages with mTLS security. The solution includes:

1. A script to generate Go code from Protocol Buffer definitions
2. A configuration system that reads from environment variables and files
3. A Kafka consumer that uses goroutines for concurrency
4. A message processor that handles specific message types
5. An HTTP server for additional functionality
6. Clean separation of concerns with a composable architecture

Key features:

- Each Kafka topic is processed in its own goroutine
- mTLS certificates are used for secure Kafka connections
- The system is configurable via environment variables
- The message handling is pluggable and extensible
- The service handles graceful shutdown

You can extend this foundation by:

- Adding more message types and their handlers
- Implementing database connections for persistent storage
- Adding more HTTP endpoints for additional functionality
- Implementing metrics and monitoring
- Adding unit and integration tests

This architecture allows you to scale horizontally by adding more instances of your service, as each will join the same consumer group and Kafka will automatically distribute the partition load.
