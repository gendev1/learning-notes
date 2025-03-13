#!/bin/sh
# Simple script to generate Protocol Buffer code for Kafka consumers
# Usage: ./simple_proto_gen.sh <topic_name> <proto_repo_path> <output_repo_path>

# Exit on error
set -e

# Check arguments
if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <topic_name> <proto_repo_path> <output_repo_path>"
  echo "Example: $0 my-topic ~/proto-repo ~/go-service"
  exit 1
fi

TOPIC="$1"
PROTO_REPO="$2"
OUTPUT_REPO="$3"
MAPPER_FILE="audit_topic_mapper.json"

echo "Starting proto code generation for topic: $TOPIC"
echo "Proto repo: $PROTO_REPO"
echo "Output repo: $OUTPUT_REPO"

# Check if required tools are installed
for cmd in jq protoc; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Error: $cmd is required but not installed"
    exit 1
  fi
done

# Check if the mapper file exists
if [ ! -f "$PROTO_REPO/$MAPPER_FILE" ]; then
  echo "Error: Mapper file not found at $PROTO_REPO/$MAPPER_FILE"
  exit 1
fi

# Create output directories
GENERATED_DIR="$OUTPUT_REPO/internal/proto/generated"
KAFKA_DIR="$OUTPUT_REPO/internal/kafka"
MODELS_DIR="$OUTPUT_REPO/internal/models"
EXAMPLES_DIR="$OUTPUT_REPO/examples"

mkdir -p "$GENERATED_DIR" "$KAFKA_DIR" "$MODELS_DIR" "$EXAMPLES_DIR"

# Extract message classes for the topic from the mapper file
echo "Reading topic mapping from $PROTO_REPO/$MAPPER_FILE"

MESSAGE_CLASSES=$(jq -r ".[] | select(.topic == \"$TOPIC\") | .messageTypes[] | .className" "$PROTO_REPO/$MAPPER_FILE")

if [ -z "$MESSAGE_CLASSES" ]; then
  echo "Error: No message classes found for topic '$TOPIC' in the mapper file"
  exit 1
fi

echo "Found message classes for topic '$TOPIC': $MESSAGE_CLASSES"

# Create a temporary build directory
BUILD_DIR=$(mktemp -d)
echo "Using temporary build directory: $BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Find all proto files and their imports
echo "Collecting proto files and dependencies..."

# Create temp files to store proto paths
PROTO_LIST=$(mktemp)
IMPORT_LIST=$(mktemp)
REQUIRED_LIST=$(mktemp)
trap 'rm -rf "$BUILD_DIR" "$PROTO_LIST" "$IMPORT_LIST" "$REQUIRED_LIST"' EXIT

# Find all proto files in the repo
find "$PROTO_REPO" -name "*.proto" > "$PROTO_LIST"

# For each message class, find the proto file
for message_class in $MESSAGE_CLASSES; do
  echo "Looking for message class: $message_class"
  FOUND=0
  
  while read -r proto_file; do
    if grep -q "message\s\+$message_class\s*{" "$proto_file"; then
      echo "Found $message_class in $proto_file"
      echo "$proto_file" >> "$REQUIRED_LIST"
      FOUND=1
      break
    fi
  done < "$PROTO_LIST"
  
  if [ "$FOUND" -eq 0 ]; then
    echo "Warning: Could not find proto file for message type $message_class"
  fi
done

# Process imports recursively
process_imports() {
  while read -r proto_file; do
    # Extract imports from the proto file
    grep -E '^import\s+"[^"]+";' "$proto_file" | sed 's/import\s\+"\([^"]\+\)".*/\1/' > "$IMPORT_LIST"
    
    # For each import, find the actual file
    while read -r import_path; do
      if [ -n "$import_path" ]; then
        # Find the actual proto file for this import
        while read -r potential_file; do
          if echo "$potential_file" | grep -q "$import_path\$"; then
            # Check if it's already in the required list
            if ! grep -q "^$potential_file\$" "$REQUIRED_LIST"; then
              echo "$potential_file" >> "$REQUIRED_LIST"
              # Process imports from this file as well
              process_imports_for_file "$potential_file"
            fi
            break
          fi
        done < "$PROTO_LIST"
      fi
    done < "$IMPORT_LIST"
  done
}

# Helper function to process imports for a single file
process_imports_for_file() {
  local single_file="$1"
  echo "$single_file" > "$IMPORT_LIST.tmp"
  mv "$IMPORT_LIST.tmp" "$IMPORT_LIST"
  process_imports
}

# Start processing imports
cp "$REQUIRED_LIST" "$IMPORT_LIST"
process_imports

echo "Required proto files:"
cat "$REQUIRED_LIST"

# Try to determine the proto root directory
echo "Determining proto root directory..."

PROTO_ROOT="$PROTO_REPO"
echo "Using proto root: $PROTO_ROOT"

# Copy required proto files to build directory
echo "Copying proto files to build directory..."

while read -r proto_file; do
  # Get relative path from proto root
  rel_path="${proto_file#$PROTO_ROOT/}"
  
  # Create directory structure in build directory
  mkdir -p "$BUILD_DIR/$(dirname "$rel_path")"
  
  # Copy the file
  cp "$proto_file" "$BUILD_DIR/$(dirname "$rel_path")/"
done < "$REQUIRED_LIST"

# Run protoc to generate Go code
echo "Generating Go code with protoc..."

find "$BUILD_DIR" -name "*.proto" | xargs protoc \
  --proto_path="$BUILD_DIR" \
  --go_out="$GENERATED_DIR" \
  --go_opt=paths=source_relative

# Check if we should generate gRPC code
if find "$BUILD_DIR" -name "*.proto" -exec grep -l "service\s\+[A-Za-z0-9_]\+" {} \; | grep -q .; then
  echo "Found service definitions, generating gRPC code..."
  find "$BUILD_DIR" -name "*.proto" | xargs protoc \
    --proto_path="$BUILD_DIR" \
    --go-grpc_out="$GENERATED_DIR" \
    --go-grpc_opt=paths=source_relative
fi

# Generate models file
echo "Generating models.go..."

cat > "$MODELS_DIR/messages.go" << EOF
// Code generated for topic $TOPIC - DO NOT EDIT.
package models

import (
	// Update this import path to match your project structure
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
)

// MessageHandler defines the interface for handling different message types
type MessageHandler interface {
EOF

# Add message handler methods
for message_class in $MESSAGE_CLASSES; do
  echo "	Handle${message_class}(*generated.${message_class}) error" >> "$MODELS_DIR/messages.go"
done

cat >> "$MODELS_DIR/messages.go" << EOF
}

// TopicConfig defines configuration for a Kafka topic
type TopicConfig struct {
	TopicName string
	GroupID   string
	TenantIDs []string
}

// MessageTypeInfo contains information about a message type
type MessageTypeInfo struct {
	PublisherName string
	ClassName     string
	MessageTypeID string
}
EOF

# Generate message processor
echo "Generating message_processor.go..."

cat > "$KAFKA_DIR/message_processor.go" << EOF
// Code generated - DO NOT EDIT.
package kafka

import (
	"fmt"
	"log"

	"google.golang.org/protobuf/proto"
	
	// Update these import paths to match your project structure
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")/internal/models"
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
)

// MessageProcessor processes messages from Kafka topics
type MessageProcessor struct {
	handler models.MessageHandler
	// Map of topic to message types info
	topicMessageTypes map[string][]models.MessageTypeInfo
}

// NewMessageProcessor creates a new message processor
func NewMessageProcessor(handler models.MessageHandler) *MessageProcessor {
	return &MessageProcessor{
		handler:           handler,
		topicMessageTypes: make(map[string][]models.MessageTypeInfo),
	}
}

// RegisterTopic registers a topic with its message types
func (p *MessageProcessor) RegisterTopic(topic string, messageTypes []models.MessageTypeInfo) {
	p.topicMessageTypes[topic] = messageTypes
	log.Printf("Registered topic %s with %d message types", topic, len(messageTypes))
}

// ProcessMessage processes a message based on its type
func (p *MessageProcessor) ProcessMessage(topic string, data []byte) error {
	log.Printf("Processing message from topic: %s", topic)

	// Get message types for this topic
	messageTypes, ok := p.topicMessageTypes[topic]
	if !ok {
		return fmt.Errorf("no message types registered for topic: %s", topic)
	}
	
	// Attempt to unmarshal based on registered message types
	// This approach requires trying each message type until one works
	// You may need to adapt this based on your actual protocol buffer structure
	
	for _, msgType := range messageTypes {
		switch msgType.ClassName {
EOF

# Add message type cases
for message_class in $MESSAGE_CLASSES; do
  cat >> "$KAFKA_DIR/message_processor.go" << EOF
		case "${message_class}":
			var msg generated.${message_class}
			if err := proto.Unmarshal(data, &msg); err != nil {
				// Try next message type
				continue
			}
			return p.handler.Handle${message_class}(&msg)
EOF
done

cat >> "$KAFKA_DIR/message_processor.go" << EOF
		}
	}
	
	return fmt.Errorf("failed to process message: no matching message type found")
}
EOF

# Generate consumer manager
echo "Generating consumer.go..."

cat > "$KAFKA_DIR/consumer.go" << EOF
// Code generated - DO NOT EDIT.
package kafka

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	
	// Update this import path to match your project structure
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")/internal/models"
)

// MessageChannel is a channel for Kafka messages
type MessageChannel chan *kafka.Message

// Consumer manages Kafka consumer instances
type Consumer struct {
	kafkaConfig  *kafka.ConfigMap
	processor    *MessageProcessor
	consumers    map[string]*kafka.Consumer
	channels     map[string]MessageChannel
	wg           sync.WaitGroup
	mu           sync.Mutex
}

// NewConsumer creates a new Kafka consumer manager
func NewConsumer(
	bootstrapServers string,
	groupIDPrefix string,
	certPath string,
	keyPath string,
	caPath string,
	handler models.MessageHandler,
) (*Consumer, error) {
	kafkaConfig := &kafka.ConfigMap{
		"bootstrap.servers":        bootstrapServers,
		"auto.offset.reset":        "earliest",
		"enable.auto.commit":       true,
		"security.protocol":        "ssl",
		"ssl.certificate.location": certPath,
		"ssl.key.location":         keyPath,
		"ssl.ca.location":          caPath,
	}

	processor := NewMessageProcessor(handler)
	
	return &Consumer{
		kafkaConfig: kafkaConfig,
		processor:   processor,
		consumers:   make(map[string]*kafka.Consumer),
		channels:    make(map[string]MessageChannel),
	}, nil
}

// AddTopic adds a topic to consume from
func (c *Consumer) AddTopic(ctx context.Context, config models.TopicConfig) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	// Check if we're already consuming from this topic
	if _, exists := c.consumers[config.TopicName]; exists {
		return fmt.Errorf("already consuming from topic: %s", config.TopicName)
	}
	
	// Create a copy of the Kafka config and set the group ID
	consumerConfig := *c.kafkaConfig
	if err := consumerConfig.SetKey("group.id", config.GroupID); err != nil {
		return fmt.Errorf("failed to set group ID: %w", err)
	}
	
	// Create the consumer
	consumer, err := kafka.NewConsumer(&consumerConfig)
	if err != nil {
		return fmt.Errorf("failed to create consumer for topic %s: %w", config.TopicName, err)
	}
	
	// Subscribe to the topic
	if err := consumer.Subscribe(config.TopicName, nil); err != nil {
		consumer.Close()
		return fmt.Errorf("failed to subscribe to topic %s: %w", config.TopicName, err)
	}
	
	// Create message channel
	messageCh := make(MessageChannel, 100)
	
	// Store the consumer and channel
	c.consumers[config.TopicName] = consumer
	c.channels[config.TopicName] = messageCh
	
	// Start consuming messages
	c.wg.Add(2)
	go c.consumeMessages(ctx, consumer, config.TopicName, messageCh)
	go c.processMessageChannel(ctx, config.TopicName, messageCh)
	
	log.Printf("Started consuming from topic: %s", config.TopicName)
	return nil
}

// Stop stops all consumers
func (c *Consumer) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()
	
	// Close all consumers
	for topic, consumer := range c.consumers {
		log.Printf("Closing consumer for topic: %s", topic)
		consumer.Close()
	}
	
	// Close all channels
	for topic, ch := range c.channels {
		log.Printf("Closing channel for topic: %s", topic)
		close(ch)
	}
	
	// Wait for all goroutines to finish
	c.wg.Wait()
	
	// Clear the maps
	c.consumers = make(map[string]*kafka.Consumer)
	c.channels = make(map[string]MessageChannel)
}

// consumeMessages consumes messages from a topic
func (c *Consumer) consumeMessages(ctx context.Context, consumer *kafka.Consumer, topic string, messageCh MessageChannel) {
	defer c.wg.Done()
	
	for {
		select {
		case <-ctx.Done():
			log.Printf("Context cancelled for topic: %s", topic)
			return
		default:
			msg, err := consumer.ReadMessage(100 * time.Millisecond)
			if err != nil {
				if err.(kafka.Error).Code() == kafka.ErrTimedOut {
					// Timeout is expected, continue
					continue
				}
				
				// Check if context is cancelled
				select {
				case <-ctx.Done():
					return
				default:
					log.Printf("Error reading message from topic %s: %v", topic, err)
					continue
				}
			}
			
			// Send message to channel
			select {
			case messageCh <- msg:
				// Message sent
			case <-ctx.Done():
				return
			}
		}
	}
}

// processMessageChannel processes messages from a channel
func (c *Consumer) processMessageChannel(ctx context.Context, topic string, messageCh MessageChannel) {
	defer c.wg.Done()
	
	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-messageCh:
			if !ok {
				// Channel closed
				return
			}
			
			// Process the message
			if err := c.processor.ProcessMessage(topic, msg.Value); err != nil {
				log.Printf("Error processing message from topic %s: %v", topic, err)
			}
		}
	}
}
EOF

# Generate example usage
echo "Generating example usage..."

cat > "$EXAMPLES_DIR/kafka_consumer_example.go" << EOF
// Example usage of the Kafka consumer
package main

import (
	"context"
	"encoding/json"
	"io/ioutil"
	"log"
	"os"
	"os/signal"
	"syscall"

	// Update these import paths to match your project structure
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")/internal/kafka"
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")/internal/models"
	"$(go list -m 2>/dev/null || echo "github.com/yourusername/myservice")$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
)

// TopicMapping represents a mapping between a Kafka topic and message types
type TopicMapping struct {
	Topic        string                  \`json:"topic"\`
	TenantIDs    []string                \`json:"tenantIds"\`
	MessageTypes []models.MessageTypeInfo \`json:"messageTypes"\`
}

// MessageHandlerImpl implements the models.MessageHandler interface
type MessageHandlerImpl struct {
	// Add any dependencies your handler needs
}

EOF

# Add message handler implementations
for message_class in $MESSAGE_CLASSES; do
  cat >> "$EXAMPLES_DIR/kafka_consumer_example.go" << EOF
// Handle${message_class} processes ${message_class} messages
func (h *MessageHandlerImpl) Handle${message_class}(msg *generated.${message_class}) error {
	log.Printf("Received ${message_class} message")
	// Implement your message handling logic here
	return nil
}
EOF
done

cat >> "$EXAMPLES_DIR/kafka_consumer_example.go" << EOF

func main() {
	// Create the message handler
	handler := &MessageHandlerImpl{}

	// Create the consumer
	consumer, err := kafka.NewConsumer(
		os.Getenv("KAFKA_BOOTSTRAP_SERVERS"),
		os.Getenv("KAFKA_GROUP_ID_PREFIX"),
		os.Getenv("KAFKA_CERT_PATH"),
		os.Getenv("KAFKA_KEY_PATH"),
		os.Getenv("KAFKA_CA_PATH"),
		handler,
	)
	if err != nil {
		log.Fatalf("Failed to create consumer: %v", err)
	}

	// Create a context that can be canceled
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Load topic mappings from the mapper file
	topicMappings, err := loadTopicMappings(os.Getenv("TOPIC_MAPPER_PATH"))
	if err != nil {
		log.Fatalf("Failed to load topic mappings: %v", err)
	}

	// Register topics and start consumers
	for _, mapping := range topicMappings {
		// Register the topic with the processor
		processor := consumer.processor
		processor.RegisterTopic(mapping.Topic, mapping.MessageTypes)

		// Add the topic to the consumer
		if err := consumer.AddTopic(ctx, models.TopicConfig{
			TopicName: mapping.Topic,
			GroupID:   os.Getenv("KAFKA_GROUP_ID_PREFIX") + "-" + mapping.Topic,
			TenantIDs: mapping.TenantIDs,
		}); err != nil {
			log.Fatalf("Failed to add topic %s: %v", mapping.Topic, err)
		}
	}

	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Wait for termination signal
	<-sigChan
	log.Println("Shutting down...")

	// Cancel the context to stop consumers
	cancel()

	// Stop the consumer and wait for it to clean up
	consumer.Stop()

	log.Println("Shutdown complete")
}

// loadTopicMappings loads topic mappings from a file
func loadTopicMappings(filePath string) ([]TopicMapping, error) {
	data, err := ioutil.ReadFile(filePath)
	if err != nil {
		return nil, err
	}

	var mappings []TopicMapping
	if err := json.Unmarshal(data, &mappings); err != nil {
		return nil, err
	}

	return mappings, nil
}
EOF

echo "Done!"
echo ""
echo "Generated files:"
echo "  - Protocol Buffer Go code: $GENERATED_DIR/*.go"
echo "  - Message Processor: $KAFKA_DIR/message_processor.go"
echo "  - Consumer Manager: $KAFKA_DIR/consumer.go"
echo "  - Message Models: $MODELS_DIR/messages.go"
echo "  - Usage Example: $EXAMPLES_DIR/kafka_consumer_example.go"
echo ""
echo "Next steps:"
echo "  1. Review the generated components and customize as needed"
echo "  2. Implement the MessageHandler interface for your specific needs"
echo "  3. Set up your application to initialize and use the consumer manager"
