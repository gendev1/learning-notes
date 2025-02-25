# Consuming Multiple Protobuf Message Types from a Single Kafka Topic in Go

This tutorial will walk you through the process of creating a Go application that consumes messages from a Kafka topic where multiple types of Protocol Buffer messages are published.

## Prerequisites

- Go (1.16+)
- Docker (for running Kafka locally)
- Basic knowledge of Go, Kafka, and Protocol Buffers

## Step 1: Set Up Your Project

First, create a new directory for your project and initialize a Go module:

```bash
mkdir kafka-protobuf-consumer
cd kafka-protobuf-consumer
go mod init github.com/yourusername/kafka-protobuf-consumer
```

Install the required dependencies:

```bash
# Confluent's Kafka Go client
go get github.com/confluentinc/confluent-kafka-go/kafka

# Protocol Buffers support
go get google.golang.org/protobuf/proto
go get google.golang.org/protobuf/reflect/protoreflect
```

## Step 2: Define Your Protocol Buffer Schema

Create a directory for your protobuf definitions:

```bash
mkdir -p proto
```

Create a file `proto/messages.proto` with multiple message types:

```protobuf
syntax = "proto3";
package kafkamsgs;

option go_package = "github.com/yourusername/kafka-protobuf-consumer/proto";

// Common envelope to wrap different message types
message MessageEnvelope {
  string message_type = 1;  // The type of the message being sent
  bytes payload = 2;        // The serialized message
}

// User-related message
message UserMessage {
  int64 user_id = 1;
  string username = 2;
  string email = 3;
}

// Order-related message
message OrderMessage {
  int64 order_id = 1;
  int64 user_id = 2;
  double total_amount = 3;
  repeated OrderItem items = 4;
}

message OrderItem {
  int64 product_id = 1;
  string product_name = 2;
  int32 quantity = 3;
  double unit_price = 4;
}

// Notification-related message
message NotificationMessage {
  int64 notification_id = 1;
  int64 user_id = 2;
  string message = 3;
  NotificationType type = 4;
}

enum NotificationType {
  UNKNOWN = 0;
  INFO = 1;
  WARNING = 2;
  ERROR = 3;
}
```

Generate Go code from the protobuf definition:

```bash
# Install the protoc compiler if you haven't already
# For macOS: brew install protobuf
# For Ubuntu: apt-get install protobuf-compiler

# Install the Go protobuf plugin
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

# Generate Go code
protoc --go_out=. proto/messages.proto
```

## Step 3: Create a Kafka Producer for Testing

Create a file named `producer/main.go` to simulate sending different message types to Kafka:

```go
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"google.golang.org/protobuf/proto"
	
	pb "github.com/yourusername/kafka-protobuf-consumer/proto"
)

func main() {
	// Create Kafka producer
	p, err := kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers": "localhost:9092",
	})
	if err != nil {
		log.Fatalf("Failed to create producer: %s", err)
	}
	defer p.Close()

	// Handle delivery reports
	go func() {
		for e := range p.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					fmt.Printf("Delivery failed: %v\n", ev.TopicPartition.Error)
				} else {
					fmt.Printf("Delivered message to topic %s [%d] at offset %v\n",
						*ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
				}
			}
		}
	}()

	// Capture signals to exit cleanly
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Topic to produce to
	topic := "multi-type-messages"

	// Run until interrupted
	run := true
	counter := 0
	
	for run {
		select {
		case <-sigchan:
			run = false
		default:
			// Produce different message types in a round-robin fashion
			counter++
			msgType := counter % 3
			
			var envelope *pb.MessageEnvelope
			
			switch msgType {
			case 0:
				// Create a UserMessage
				userMsg := &pb.UserMessage{
					UserId:   int64(counter),
					Username: fmt.Sprintf("user%d", counter),
					Email:    fmt.Sprintf("user%d@example.com", counter),
				}
				
				// Serialize the user message
				userBytes, err := proto.Marshal(userMsg)
				if err != nil {
					log.Printf("Error marshaling UserMessage: %v", err)
					continue
				}
				
				envelope = &pb.MessageEnvelope{
					MessageType: "UserMessage",
					Payload:     userBytes,
				}
				
			case 1:
				// Create an OrderMessage
				orderMsg := &pb.OrderMessage{
					OrderId:     int64(counter),
					UserId:      int64(counter % 100),
					TotalAmount: 99.99,
					Items: []*pb.OrderItem{
						{
							ProductId:   1001,
							ProductName: "Product A",
							Quantity:    2,
							UnitPrice:   49.99,
						},
					},
				}
				
				// Serialize the order message
				orderBytes, err := proto.Marshal(orderMsg)
				if err != nil {
					log.Printf("Error marshaling OrderMessage: %v", err)
					continue
				}
				
				envelope = &pb.MessageEnvelope{
					MessageType: "OrderMessage",
					Payload:     orderBytes,
				}
				
			case 2:
				// Create a NotificationMessage
				notificationMsg := &pb.NotificationMessage{
					NotificationId: int64(counter),
					UserId:         int64(counter % 100),
					Message:        fmt.Sprintf("Notification %d", counter),
					Type:           pb.NotificationType_INFO,
				}
				
				// Serialize the notification message
				notifBytes, err := proto.Marshal(notificationMsg)
				if err != nil {
					log.Printf("Error marshaling NotificationMessage: %v", err)
					continue
				}
				
				envelope = &pb.MessageEnvelope{
					MessageType: "NotificationMessage",
					Payload:     notifBytes,
				}
			}
			
			// Serialize the envelope
			envelopeBytes, err := proto.Marshal(envelope)
			if err != nil {
				log.Printf("Error marshaling envelope: %v", err)
				continue
			}
			
			// Produce message to topic
			err = p.Produce(&kafka.Message{
				TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
				Value:          envelopeBytes,
				Key:            []byte(fmt.Sprintf("key-%d", counter)),
			}, nil)
			
			if err != nil {
				log.Printf("Error producing message: %v", err)
			}
			
			// Wait before sending next message
			time.Sleep(1 * time.Second)
		}
	}

	// Wait for message deliveries before shutting down
	p.Flush(15 * 1000)
	fmt.Println("Producer shutdown complete")
}
```

## Step 4: Create a Kafka Consumer for Multiple Message Types

Create a file named `consumer/main.go`:

```go
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"google.golang.org/protobuf/proto"
	
	pb "github.com/yourusername/kafka-protobuf-consumer/proto"
)

func main() {
	// Create Kafka consumer
	c, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers":  "localhost:9092",
		"group.id":           "protobuf-consumer-group",
		"auto.offset.reset":  "earliest",
		"session.timeout.ms": 6000,
	})
	if err != nil {
		log.Fatalf("Failed to create consumer: %s", err)
	}
	defer c.Close()

	// Subscribe to topic
	topic := "multi-type-messages"
	if err := c.SubscribeTopics([]string{topic}, nil); err != nil {
		log.Fatalf("Failed to subscribe to topic: %s", err)
	}
	fmt.Printf("Subscribed to topic: %s\n", topic)

	// Capture signals to exit cleanly
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Process messages
	run := true
	for run {
		select {
		case sig := <-sigchan:
			fmt.Printf("Caught signal %v: terminating\n", sig)
			run = false
		default:
			msg, err := c.ReadMessage(100 * time.Millisecond)
			if err != nil {
				// Timeout is expected when there are no messages
				if err.(kafka.Error).Code() != kafka.ErrTimedOut {
					log.Printf("Consumer error: %v\n", err)
				}
				continue
			}

			// Process the message
			fmt.Printf("Received message from topic %s [%d] at offset %v\n",
				*msg.TopicPartition.Topic, msg.TopicPartition.Partition, msg.TopicPartition.Offset)

			// Deserialize the envelope
			envelope := &pb.MessageEnvelope{}
			if err := proto.Unmarshal(msg.Value, envelope); err != nil {
				log.Printf("Error unmarshaling message envelope: %v", err)
				continue
			}

			// Process based on message type
			switch envelope.MessageType {
			case "UserMessage":
				userMsg := &pb.UserMessage{}
				if err := proto.Unmarshal(envelope.Payload, userMsg); err != nil {
					log.Printf("Error unmarshaling UserMessage: %v", err)
					continue
				}
				fmt.Printf("UserMessage: ID=%d, Username=%s, Email=%s\n",
					userMsg.UserId, userMsg.Username, userMsg.Email)

			case "OrderMessage":
				orderMsg := &pb.OrderMessage{}
				if err := proto.Unmarshal(envelope.Payload, orderMsg); err != nil {
					log.Printf("Error unmarshaling OrderMessage: %v", err)
					continue
				}
				fmt.Printf("OrderMessage: ID=%d, UserID=%d, Total=%.2f, Items=%d\n",
					orderMsg.OrderId, orderMsg.UserId, orderMsg.TotalAmount, len(orderMsg.Items))
				for i, item := range orderMsg.Items {
					fmt.Printf("  Item %d: %s (Qty: %d, Price: %.2f)\n",
						i+1, item.ProductName, item.Quantity, item.UnitPrice)
				}

			case "NotificationMessage":
				notifMsg := &pb.NotificationMessage{}
				if err := proto.Unmarshal(envelope.Payload, notifMsg); err != nil {
					log.Printf("Error unmarshaling NotificationMessage: %v", err)
					continue
				}
				fmt.Printf("NotificationMessage: ID=%d, UserID=%d, Type=%s, Message=%s\n",
					notifMsg.NotificationId, notifMsg.UserId,
					notifMsg.Type.String(), notifMsg.Message)

			default:
				log.Printf("Unknown message type: %s", envelope.MessageType)
			}
		}
	}

	fmt.Println("Consumer shutdown complete")
}
```

## Step 5: Create a Docker Compose File for Kafka

Create a file named `docker-compose.yml`:

```yaml
version: '3'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.3.0
    hostname: zookeeper
    container_name: zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000

  kafka:
    image: confluentinc/cp-kafka:7.3.0
    hostname: kafka
    container_name: kafka
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: 'zookeeper:2181'
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
```

## Step 6: Implement a Factory Pattern for Message Processing

Create a file named `consumer/handler/message_handler.go` to better organize the message handling logic:

```go
package handler

import (
	"fmt"
	"log"

	"google.golang.org/protobuf/proto"
	
	pb "github.com/yourusername/kafka-protobuf-consumer/proto"
)

// MessageHandler interface defines how to handle a specific message type
type MessageHandler interface {
	HandleMessage(payload []byte) error
}

// UserMessageHandler handles UserMessage types
type UserMessageHandler struct{}

func (h *UserMessageHandler) HandleMessage(payload []byte) error {
	msg := &pb.UserMessage{}
	if err := proto.Unmarshal(payload, msg); err != nil {
		return fmt.Errorf("error unmarshaling UserMessage: %w", err)
	}
	
	// Process the user message
	log.Printf("UserMessage: ID=%d, Username=%s, Email=%s\n",
		msg.UserId, msg.Username, msg.Email)
	
	// Add your business logic here
	
	return nil
}

// OrderMessageHandler handles OrderMessage types
type OrderMessageHandler struct{}

func (h *OrderMessageHandler) HandleMessage(payload []byte) error {
	msg := &pb.OrderMessage{}
	if err := proto.Unmarshal(payload, msg); err != nil {
		return fmt.Errorf("error unmarshaling OrderMessage: %w", err)
	}
	
	// Process the order message
	log.Printf("OrderMessage: ID=%d, UserID=%d, Total=%.2f, Items=%d\n",
		msg.OrderId, msg.UserId, msg.TotalAmount, len(msg.Items))
	
	for i, item := range msg.Items {
		log.Printf("  Item %d: %s (Qty: %d, Price: %.2f)\n",
			i+1, item.ProductName, item.Quantity, item.UnitPrice)
	}
	
	// Add your business logic here
	
	return nil
}

// NotificationMessageHandler handles NotificationMessage types
type NotificationMessageHandler struct{}

func (h *NotificationMessageHandler) HandleMessage(payload []byte) error {
	msg := &pb.NotificationMessage{}
	if err := proto.Unmarshal(payload, msg); err != nil {
		return fmt.Errorf("error unmarshaling NotificationMessage: %w", err)
	}
	
	// Process the notification message
	log.Printf("NotificationMessage: ID=%d, UserID=%d, Type=%s, Message=%s\n",
		msg.NotificationId, msg.UserId,
		msg.Type.String(), msg.Message)
	
	// Add your business logic here
	
	return nil
}

// MessageHandlerFactory creates the appropriate handler for a message type
func GetMessageHandler(messageType string) (MessageHandler, error) {
	switch messageType {
	case "UserMessage":
		return &UserMessageHandler{}, nil
	case "OrderMessage":
		return &OrderMessageHandler{}, nil
	case "NotificationMessage":
		return &NotificationMessageHandler{}, nil
	default:
		return nil, fmt.Errorf("unknown message type: %s", messageType)
	}
}
```

## Step 7: Update the Consumer to Use the Message Handler

Update the `consumer/main.go` file to use our new message handler factory:

```go
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"google.golang.org/protobuf/proto"
	
	"github.com/yourusername/kafka-protobuf-consumer/consumer/handler"
	pb "github.com/yourusername/kafka-protobuf-consumer/proto"
)

func main() {
	// Create Kafka consumer
	c, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers":  "localhost:9092",
		"group.id":           "protobuf-consumer-group",
		"auto.offset.reset":  "earliest",
		"session.timeout.ms": 6000,
	})
	if err != nil {
		log.Fatalf("Failed to create consumer: %s", err)
	}
	defer c.Close()

	// Subscribe to topic
	topic := "multi-type-messages"
	if err := c.SubscribeTopics([]string{topic}, nil); err != nil {
		log.Fatalf("Failed to subscribe to topic: %s", err)
	}
	fmt.Printf("Subscribed to topic: %s\n", topic)

	// Capture signals to exit cleanly
	sigchan := make(chan os.Signal, 1)
	signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

	// Process messages
	run := true
	for run {
		select {
		case sig := <-sigchan:
			fmt.Printf("Caught signal %v: terminating\n", sig)
			run = false
		default:
			msg, err := c.ReadMessage(100 * time.Millisecond)
			if err != nil {
				// Timeout is expected when there are no messages
				if err.(kafka.Error).Code() != kafka.ErrTimedOut {
					log.Printf("Consumer error: %v\n", err)
				}
				continue
			}

			// Process the message
			fmt.Printf("Received message from topic %s [%d] at offset %v\n",
				*msg.TopicPartition.Topic, msg.TopicPartition.Partition, msg.TopicPartition.Offset)

			// Deserialize the envelope
			envelope := &pb.MessageEnvelope{}
			if err := proto.Unmarshal(msg.Value, envelope); err != nil {
				log.Printf("Error unmarshaling message envelope: %v", err)
				continue
			}

			// Get the appropriate handler for this message type
			msgHandler, err := handler.GetMessageHandler(envelope.MessageType)
			if err != nil {
				log.Printf("Error getting message handler: %v", err)
				continue
			}

			// Handle the message
			if err := msgHandler.HandleMessage(envelope.Payload); err != nil {
				log.Printf("Error handling message: %v", err)
			}
		}
	}

	fmt.Println("Consumer shutdown complete")
}
```

## Step 8: Running the Application

1. Start Kafka using Docker Compose:

```bash
docker-compose up -d
```

2. Build and run the consumer:

```bash
cd consumer
go build -o consumer
./consumer
```

3. In a separate terminal, build and run the producer:

```bash
cd producer
go build -o producer
./producer
```

The producer will start sending messages of different types to the Kafka topic, and the consumer will process them accordingly.

## Advanced Topics

### 1. Using Schema Registry

For production environments, consider using Confluent's Schema Registry to manage your Protocol Buffer schemas. The Schema Registry ensures compatibility between different versions of your schema and provides a central repository for all schemas.

```go
// Example of using Schema Registry with Protocol Buffers
import (
    "github.com/confluentinc/confluent-kafka-go/schemaregistry"
    "github.com/confluentinc/confluent-kafka-go/schemaregistry/serde"
    "github.com/confluentinc/confluent-kafka-go/schemaregistry/serde/protobuf"
)

// Initialize Schema Registry client
srClient, err := schemaregistry.NewClient(schemaregistry.NewConfig("http://localhost:8081"))
if err != nil {
    log.Fatalf("Failed to create schema registry client: %s", err)
}

// Create Protobuf serializer/deserializer
ser, err := protobuf.NewSerializer(srClient, serde.ValueSerde, protobuf.NewSerializerConfig())
if err != nil {
    log.Fatalf("Failed to create serializer: %s", err)
}

deser, err := protobuf.NewDeserializer(srClient, serde.ValueSerde, protobuf.NewDeserializerConfig())
if err != nil {
    log.Fatalf("Failed to create deserializer: %s", err)
}
```

### 2. Dynamic Message Type Resolution

Instead of hardcoding message types, you can use Protocol Buffers' reflection capabilities to dynamically resolve message types:

```go
import (
    "google.golang.org/protobuf/reflect/protodesc"
    "google.golang.org/protobuf/reflect/protoreflect"
    "google.golang.org/protobuf/reflect/protoregistry"
)

// Register your message types
protoregistry.GlobalTypes.RegisterMessage((&pb.UserMessage{}).ProtoReflect().Type())
protoregistry.GlobalTypes.RegisterMessage((&pb.OrderMessage{}).ProtoReflect().Type())
protoregistry.GlobalTypes.RegisterMessage((&pb.NotificationMessage{}).ProtoReflect().Type())

// Create a new message of the specified type
func createMessageByName(typeName string) (proto.Message, error) {
    msgType, err := protoregistry.GlobalTypes.FindMessageByName(protoreflect.FullName(typeName))
    if err != nil {
        return nil, err
    }
    return proto.Message(msgType.New().Interface()), nil
}
```

### 3. Error Handling and Retries

In production environments, you'll want to implement robust error handling and retry mechanisms:

```go
// Configure consumer with error handling
c, err := kafka.NewConsumer(&kafka.ConfigMap{
    "bootstrap.servers":        "localhost:9092",
    "group.id":                 "protobuf-consumer-group",
    "auto.offset.reset":        "earliest",
    "enable.auto.commit":       false,  // Disable auto commit for manual control
    "max.poll.interval.ms":     300000, // 5 minutes
    "session.timeout.ms":       10000,  // 10 seconds
    "heartbeat.interval.ms":    3000,   // 3 seconds
})

// Example of a retry mechanism
func processMessageWithRetry(msg *kafka.Message, maxRetries int) error {
    var err error
    for attempt := 0; attempt < maxRetries; attempt++ {
        err = processMessage(msg)
        if err == nil {
            // Successfully processed, commit the offset
            if _, err := c.CommitMessage(msg); err != nil {
                log.Printf("Error committing offset: %v", err)
            }
            return nil
        }
        
        // Exponential backoff
        backoff := time.Duration(math.Pow(2, float64(attempt))) * time.Second
        log.Printf("Retry %d after %v: %v", attempt+1, backoff, err)
        time.Sleep(backoff)
    }
    return fmt.Errorf("failed after %d attempts: %w", maxRetries, err)
}
```

## Conclusion

This tutorial demonstrated how to implement a Go application that can consume and process multiple types of Protocol Buffer messages from a single Kafka topic. The approach uses an envelope pattern to wrap different message types and a factory pattern to handle each message type appropriately.

For a production-ready implementation, consider integrating with Schema Registry, implementing proper error handling and retry mechanisms, and adding metrics and monitoring for your Kafka consumers.

## Resources

- [Confluent Kafka Go Client](https://github.com/confluentinc/confluent-kafka-go)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
- [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)