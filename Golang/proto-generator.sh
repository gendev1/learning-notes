#!/bin/bash

# Script to generate Protocol Buffer code for a specific Kafka topic
# Usage: ./generate_proto.sh --topic <topic-name> --proto-repo <proto-repo-path> --output-repo <go-repo-path>

set -e

# Default values
PROTO_REPO=""
OUTPUT_REPO=""
TOPIC=""
BRANCH="main"
MAPPER_FILE="audit_topic_mapper.json"
FORCE_UPDATE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --topic)
      TOPIC="$2"
      shift 2
      ;;
    --proto-repo)
      PROTO_REPO="$2"
      shift 2
      ;;
    --output-repo)
      OUTPUT_REPO="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --mapper-file)
      MAPPER_FILE="$2"
      shift 2
      ;;
    --force)
      FORCE_UPDATE=true
      shift
      ;;
    --help)
      echo "Usage: ./generate_proto.sh --topic <topic-name> --proto-repo <proto-repo-path> --output-repo <go-repo-path> [--branch <branch-name>] [--mapper-file <mapper-file-path>] [--force]"
      echo ""
      echo "Options:"
      echo "  --topic <topic-name>           Kafka topic name to generate code for"
      echo "  --proto-repo <proto-repo-path> Path or URL to the proto repository"
      echo "  --output-repo <go-repo-path>   Path to the Go microservice repository"
      echo "  --branch <branch-name>         Git branch to use (default: main)"
      echo "  --mapper-file <mapper-file>    Path to mapper file (default: audit_topic_mapper.json)"
      echo "  --force                        Force update even if repo exists"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$TOPIC" ]; then
  echo "Error: Topic name is required (--topic)"
  exit 1
fi

if [ -z "$PROTO_REPO" ]; then
  echo "Error: Proto repository path is required (--proto-repo)"
  exit 1
fi

if [ -z "$OUTPUT_REPO" ]; then
  echo "Error: Output repository path is required (--output-repo)"
  exit 1
fi

# Create a temporary directory for the proto repo if it's a URL
if [[ "$PROTO_REPO" == http* ]]; then
  TEMP_DIR=$(mktemp -d)
  REPO_URL="$PROTO_REPO"
  PROTO_REPO="$TEMP_DIR"
  
  echo "Cloning $REPO_URL to $PROTO_REPO..."
  git clone -b "$BRANCH" "$REPO_URL" "$PROTO_REPO"
  
  # Clean up on exit
  trap "rm -rf $TEMP_DIR" EXIT
fi

# Set the output directory for generated Go files
GENERATED_DIR="$OUTPUT_REPO/internal/proto/generated"
mkdir -p "$GENERATED_DIR"

# Read the topic mapper file
MAPPER_PATH="$PROTO_REPO/$MAPPER_FILE"
if [ ! -f "$MAPPER_PATH" ]; then
  echo "Error: Mapper file not found at $MAPPER_PATH"
  exit 1
fi

echo "Reading topic mapping from $MAPPER_PATH..."

# Parse the JSON to get message types for the specified topic
# This adapts to the format:
# {
#   topic: "topic-name",
#   tenantIds: [],
#   messageTypes: [
#     {
#       publisherName: "publisher",
#       className: "ProtoClassName",
#       messageTypeId: "message-type-id"
#     }
#   ]
# }
MESSAGE_CLASSES=$(jq -r ".[] | select(.topic == \"$TOPIC\") | .messageTypes[] | .className" "$MAPPER_PATH")

if [ -z "$MESSAGE_CLASSES" ]; then
  echo "Error: No message classes found for topic '$TOPIC' in the mapper file"
  exit 1
fi

echo "Found message classes for topic '$TOPIC': $MESSAGE_CLASSES"

# Find all .proto files in the repo
PROTO_FILES=$(find "$PROTO_REPO" -name "*.proto")

# Create a temporary directory for the proto build process
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

echo "Analyzing proto dependencies..."

# Function to find all imports in a proto file
find_imports() {
  local proto_file="$1"
  grep -E '^import\s+"[^"]+";' "$proto_file" | sed 's/import\s\+"\([^"]\+\)".*/\1/'
}

# Function to find message types in a proto file
find_message_types() {
  local proto_file="$1"
  grep -E '^message\s+[A-Za-z0-9_]+' "$proto_file" | sed 's/message\s\+\([A-Za-z0-9_]\+\).*/\1/'
}

# Build a map of message types to proto files
declare -A MESSAGE_TO_PROTO
for proto_file in $PROTO_FILES; do
  for message in $(find_message_types "$proto_file"); do
    MESSAGE_TO_PROTO["$message"]="$proto_file"
  done
done

# Function to collect all required proto files recursively
declare -A REQUIRED_PROTOS
collect_required_protos() {
  local proto_file="$1"
  
  # If we've already processed this file, skip it
  if [ -n "${REQUIRED_PROTOS["$proto_file"]}" ]; then
    return
  fi
  
  # Mark this file as required
  REQUIRED_PROTOS["$proto_file"]=1
  
  # Find all imports in this file
  for import in $(find_imports "$proto_file"); do
    # Find the actual file path for this import
    for potential_file in $PROTO_FILES; do
      if [[ "$potential_file" == *"$import" ]]; then
        collect_required_protos "$potential_file"
        break
      fi
    done
  done
}

# Collect all required proto files for each message ID
for message_id in $MESSAGE_IDS; do
  proto_file="${MESSAGE_TO_PROTO["$message_id"]}"
  if [ -n "$proto_file" ]; then
    echo "Found proto file for $message_id: $proto_file"
    collect_required_protos "$proto_file"
  else
    echo "Warning: Could not find proto file for message type $message_id"
    # Try searching for the message in all proto files
    for proto_file in $PROTO_FILES; do
      if grep -q "message\s\+$message_id\s*{" "$proto_file"; then
        echo "Found $message_id in $proto_file"
        collect_required_protos "$proto_file"
        break
      fi
    done
  fi
done

# Print all required proto files
echo "Required proto files:"
for proto_file in "${!REQUIRED_PROTOS[@]}"; do
  echo "  $proto_file"
done

# Find the common proto root directory
PROTO_ROOT="$PROTO_REPO"
for proto_file in "${!REQUIRED_PROTOS[@]}"; do
  # Get the relative path of the proto file
  rel_path="${proto_file#$PROTO_REPO/}"
  
  # Find the deepest common directory
  while [ -n "$rel_path" ]; do
    potential_root="$PROTO_REPO/${rel_path%/*}"
    if [ -d "$potential_root" ]; then
      # Check if all imports can be resolved from this root
      all_imports_resolve=true
      for proto in "${!REQUIRED_PROTOS[@]}"; do
        for import in $(find_imports "$proto"); do
          if [ ! -f "$potential_root/$import" ]; then
            all_imports_resolve=false
            break 2
          fi
        done
      done
      
      if [ "$all_imports_resolve" = true ]; then
        PROTO_ROOT="$potential_root"
        break
      fi
    fi
    # Move up one directory
    rel_path="${rel_path%/*}"
  done
done

echo "Using proto root directory: $PROTO_ROOT"

# Copy all required proto files to the build directory
for proto_file in "${!REQUIRED_PROTOS[@]}"; do
  # Get relative path from PROTO_ROOT
  rel_path="${proto_file#$PROTO_ROOT/}"
  
  # Create directory structure in build directory
  mkdir -p "$BUILD_DIR/$(dirname "$rel_path")"
  
  # Copy the file
  cp "$proto_file" "$BUILD_DIR/$(dirname "$rel_path")/"
done

# Run protoc to generate the Go code
echo "Generating Go code..."
find "$BUILD_DIR" -name "*.proto" -print0 | xargs -0 protoc \
  --proto_path="$BUILD_DIR" \
  --go_out="$GENERATED_DIR" \
  --go_opt=paths=source_relative

# Check if we need to generate gRPC code
if grep -q "service\s\+[A-Za-z0-9_]\+" $(find "$BUILD_DIR" -name "*.proto"); then
  echo "Found service definitions, generating gRPC code..."
  find "$BUILD_DIR" -name "*.proto" -print0 | xargs -0 protoc \
    --proto_path="$BUILD_DIR" \
    --go-grpc_out="$GENERATED_DIR" \
    --go-grpc_opt=paths=source_relative
fi

# Generate a message processor for the specified topic
KAFKA_DIR="$OUTPUT_REPO/internal/kafka"
MODELS_DIR="$OUTPUT_REPO/internal/models"
mkdir -p "$KAFKA_DIR" "$MODELS_DIR"

echo "Generating message processor components..."

# First, create a models file with message type definitions
cat > "$MODELS_DIR/messages.go" << EOF
// Code generated for topic $TOPIC - DO NOT EDIT.
package models

import (
	// Update this import path to match your project structure
	"$(go list -m)$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
)

// MessageHandler defines the interface for handling different message types
type MessageHandler interface {
$(for message_class in $MESSAGE_CLASSES; do
  echo "	Handle${message_class}(*generated.${message_class}) error"
done)
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

# Now create a message processor that can handle multiple topics
cat > "$KAFKA_DIR/message_processor.go" << EOF
// Code generated - DO NOT EDIT.
package kafka

import (
	"fmt"
	"log"

	"google.golang.org/protobuf/proto"
	
	// Update these import paths to match your project structure
	"$(go list -m)/internal/models"
	"$(go list -m)$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
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
$(for message_class in $MESSAGE_CLASSES; do
  echo "		case \"${message_class}\":
			var msg generated.${message_class}
			if err := proto.Unmarshal(data, &msg); err != nil {
				// Try next message type
				continue
			}
			return p.handler.Handle${message_class}(&msg)"
done)
		}
	}
	
	/* Alternative approach if you have a wrapper message
	var wrapper generated.MessageWrapper
	if err := proto.Unmarshal(data, &wrapper); err != nil {
		return fmt.Errorf("failed to unmarshal message wrapper: %w", err)
	}
	
	// Process based on which oneof field is set
$(for message_class in $MESSAGE_CLASSES; do
  echo "	if msg := wrapper.Get${message_class}(); msg != nil {
		return p.handler.Handle${message_class}(msg)
	}"
done)
	*/
	
	/* Alternative approach if you have a header with message type ID
	var header generated.Header
	if err := proto.Unmarshal(data, &header); err != nil {
		return fmt.Errorf("failed to unmarshal header: %w", err)
	}
	
	// Find message type matching the ID
	for _, msgType := range messageTypes {
		if msgType.MessageTypeID == header.GetMessageType() {
			switch msgType.ClassName {
$(for message_class in $MESSAGE_CLASSES; do
  echo "			case \"${message_class}\":
				var msg generated.${message_class}
				if err := proto.Unmarshal(data, &msg); err != nil {
					return fmt.Errorf(\"failed to unmarshal %s: %w\", msgType.ClassName, err)
				}
				return p.handler.Handle${message_class}(&msg)"
done)
			}
		}
	}
	
	return fmt.Errorf("unknown message type: %s", header.GetMessageType())
	*/
	
	return fmt.Errorf("failed to process message: no matching message type found")
}
EOF

# Create a consumer manager that can handle multiple topics
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
	"$(go list -m)/internal/models"
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

# Generate a simple example of how to use the message processor
mkdir -p "$OUTPUT_REPO/examples"
cat > "$OUTPUT_REPO/examples/kafka_consumer_example.go" << EOF
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
	"$(go list -m)/internal/kafka"
	"$(go list -m)/internal/models"
	"$(go list -m)$(echo $GENERATED_DIR | sed "s|$OUTPUT_REPO||")"
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

$(for message_class in $MESSAGE_CLASSES; do
echo "// Handle${message_class} processes ${message_class} messages
func (h *MessageHandlerImpl) Handle${message_class}(msg *generated.${message_class}) error {
	log.Printf(\"Received ${message_class} message\")
	// Implement your message handling logic here
	return nil
}"
done)

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

	// Create the message processor
	processor := kafka.NewMessageProcessor(handler)

	// Register topics and start consumers
	for _, mapping := range topicMappings {
		// Register the topic with the processor
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
echo "  - Usage Example: $OUTPUT_REPO/examples/kafka_consumer_example.go"
echo ""
echo "Next steps:"
echo "  1. Review the generated components and customize as needed"
echo "  2. Implement the MessageHandler interface for your specific needs"
echo "  3. Set up your application to initialize and use the consumer manager"
