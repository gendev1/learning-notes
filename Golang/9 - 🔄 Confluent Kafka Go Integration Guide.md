

## 🚀 Setup and Installation

### Prerequisites
```bash
# Install librdkafka development files
# For Ubuntu/Debian
apt-get install librdkafka-dev

# For macOS
brew install librdkafka

# Install the Go library
go get github.com/confluentinc/confluent-kafka-go/kafka
```

### Basic Configuration
```go
package main

import (
    "github.com/confluentinc/confluent-kafka-go/kafka"
    "github.com/confluentinc/confluent-kafka-go/schemaregistry"
    "github.com/confluentinc/confluent-kafka-go/schemaregistry/serde/protobuf"
)

// Configuration helper
func getKafkaConfig() *kafka.ConfigMap {
    return &kafka.ConfigMap{
        "bootstrap.servers":        "localhost:9092",
        "security.protocol":        "SASL_SSL",
        "sasl.mechanisms":          "PLAIN",
        "sasl.username":           "${KAFKA_USERNAME}",
        "sasl.password":           "${KAFKA_PASSWORD}",
        "enable.idempotence":      true,
        "auto.offset.reset":       "earliest",
        "message.send.max.retries": 10000,
    }
}
```

## 📤 Producer Implementation

### Basic Producer
```go
type Producer struct {
    producer *kafka.Producer
    topic    string
}

func NewProducer(config *kafka.ConfigMap, topic string) (*Producer, error) {
    p, err := kafka.NewProducer(config)
    if err != nil {
        return nil, err
    }

    // Start delivery report goroutine
    go func() {
        for e := range p.Events() {
            switch ev := e.(type) {
            case *kafka.Message:
                if ev.TopicPartition.Error != nil {
                    log.Printf("Delivery failed: %v\n", ev.TopicPartition.Error)
                } else {
                    log.Printf("Delivered message to topic %s [%d] at offset %v\n",
                        *ev.TopicPartition.Topic, ev.TopicPartition.Partition, ev.TopicPartition.Offset)
                }
            case kafka.Error:
                log.Printf("Error: %v\n", ev)
            }
        }
    }()

    return &Producer{
        producer: p,
        topic:    topic,
    }, nil
}

func (p *Producer) Close() {
    p.producer.Flush(15 * 1000)  // 15 seconds timeout
    p.producer.Close()
}

func (p *Producer) ProduceMessage(key string, value []byte) error {
    return p.producer.Produce(&kafka.Message{
        TopicPartition: kafka.TopicPartition{
            Topic:     &p.topic,
            Partition: kafka.PartitionAny,
        },
        Key:   []byte(key),
        Value: value,
    }, nil)
}
```

### Protobuf Producer
```go
type ProtoProducer struct {
    producer   *kafka.Producer
    serializer *protobuf.Serializer
    topic      string
}

func NewProtoProducer(config *kafka.ConfigMap, topic string, schemaRegistryURL string) (*ProtoProducer, error) {
    // Create Schema Registry client
    srClient, err := schemaregistry.NewClient(schemaregistry.NewConfig(
        schemaRegistryURL,
    ))
    if err != nil {
        return nil, err
    }

    // Create Protobuf serializer
    serializer, err := protobuf.NewSerializer(srClient, serde.ValueSerde, 
        protobuf.NewSerializerConfig())
    if err != nil {
        return nil, err
    }

    // Create producer
    p, err := kafka.NewProducer(config)
    if err != nil {
        return nil, err
    }

    return &ProtoProducer{
        producer:   p,
        serializer: serializer,
        topic:      topic,
    }, nil
}

func (p *ProtoProducer) ProduceProtoMessage(key string, msg proto.Message) error {
    // Serialize the protobuf message
    payload, err := p.serializer.Serialize(p.topic, msg)
    if err != nil {
        return err
    }

    return p.producer.Produce(&kafka.Message{
        TopicPartition: kafka.TopicPartition{
            Topic:     &p.topic,
            Partition: kafka.PartitionAny,
        },
        Key:   []byte(key),
        Value: payload,
    }, nil)
}
```

## 📥 Consumer Implementation

### Consumer Group
```go
type Consumer struct {
    consumer *kafka.Consumer
    topics   []string
    running  bool
    quit     chan struct{}
}

func NewConsumer(config *kafka.ConfigMap, topics []string) (*Consumer, error) {
    c, err := kafka.NewConsumer(config)
    if err != nil {
        return nil, err
    }

    err = c.SubscribeTopics(topics, nil)
    if err != nil {
        c.Close()
        return nil, err
    }

    return &Consumer{
        consumer: c,
        topics:   topics,
        quit:     make(chan struct{}),
    }, nil
}

func (c *Consumer) Start(handler func(*kafka.Message) error) {
    c.running = true
    
    go func() {
        for c.running {
            select {
            case <-c.quit:
                return
            default:
                msg, err := c.consumer.ReadMessage(-1)
                if err != nil {
                    if !c.running {
                        return
                    }
                    log.Printf("Consumer error: %v\n", err)
                    continue
                }

                if err := handler(msg); err != nil {
                    log.Printf("Handler error: %v\n", err)
                    // Implement your error handling strategy here
                }
            }
        }
    }()
}

func (c *Consumer) Close() {
    c.running = false
    close(c.quit)
    c.consumer.Close()
}
```

### Protobuf Consumer
```go
type ProtoConsumer struct {
    consumer    *kafka.Consumer
    deserializer *protobuf.Deserializer
    topics      []string
    running     bool
    quit        chan struct{}
}

func NewProtoConsumer(config *kafka.ConfigMap, topics []string, schemaRegistryURL string) (*ProtoConsumer, error) {
    // Create Schema Registry client
    srClient, err := schemaregistry.NewClient(schemaregistry.NewConfig(
        schemaRegistryURL,
    ))
    if err != nil {
        return nil, err
    }

    // Create Protobuf deserializer
    deserializer, err := protobuf.NewDeserializer(srClient, serde.ValueSerde,
        protobuf.NewDeserializerConfig())
    if err != nil {
        return nil, err
    }

    // Create consumer
    c, err := kafka.NewConsumer(config)
    if err != nil {
        return nil, err
    }

    err = c.SubscribeTopics(topics, nil)
    if err != nil {
        c.Close()
        return nil, err
    }

    return &ProtoConsumer{
        consumer:     c,
        deserializer: deserializer,
        topics:       topics,
        quit:        make(chan struct{}),
    }, nil
}

func (c *ProtoConsumer) Start(handler func(proto.Message) error) {
    c.running = true
    
    go func() {
        for c.running {
            select {
            case <-c.quit:
                return
            default:
                msg, err := c.consumer.ReadMessage(-1)
                if err != nil {
                    if !c.running {
                        return
                    }
                    log.Printf("Consumer error: %v\n", err)
                    continue
                }

                // Deserialize the protobuf message
                var protoMsg proto.Message
                err = c.deserializer.DeserializeInto(msg.TopicPartition.Topic, msg.Value, &protoMsg)
                if err != nil {
                    log.Printf("Deserialization error: %v\n", err)
                    continue
                }

                if err := handler(protoMsg); err != nil {
                    log.Printf("Handler error: %v\n", err)
                }
            }
        }
    }()
}
```

## 🔄 Complete Example

### With Protobuf Messages
```go
func main() {
    // Kafka configuration
    config := &kafka.ConfigMap{
        "bootstrap.servers": "localhost:9092",
        "group.id":         "test-group",
        "auto.offset.reset": "earliest",
    }

    // Create producer
    producer, err := NewProtoProducer(config, "test-topic", "http://localhost:8081")
    if err != nil {
        log.Fatal(err)
    }
    defer producer.Close()

    // Create consumer
    consumer, err := NewProtoConsumer(config, []string{"test-topic"}, "http://localhost:8081")
    if err != nil {
        log.Fatal(err)
    }
    defer consumer.Close()

    // Start consumer with handler
    consumer.Start(func(msg proto.Message) error {
        // Handle the protobuf message
        log.Printf("Received message: %v\n", msg)
        return nil
    })

    // Example: Produce messages in a loop
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    // Graceful shutdown
    sigchan := make(chan os.Signal, 1)
    signal.Notify(sigchan, syscall.SIGINT, syscall.SIGTERM)

    for {
        select {
        case <-ticker.C:
            msg := &YourProtoMessage{
                // Set fields
            }
            if err := producer.ProduceProtoMessage("key", msg); err != nil {
                log.Printf("Failed to produce message: %v\n", err)
            }
        case <-sigchan:
            return
        }
    }
}
```

## 💡 Best Practices

### 1. Error Handling
```go
func handleKafkaError(err kafka.Error) {
    switch err.Code() {
    case kafka.ErrQueueFull:
        // Handle local queue full
        time.Sleep(time.Second)
    case kafka.ErrTimedOut:
        // Handle timeout
        log.Printf("Operation timed out: %v\n", err)
    case kafka.ErrTransport:
        // Handle transport error
        log.Printf("Transport error: %v\n", err)
    default:
        log.Printf("Unknown error: %v\n", err)
    }
}
```

### 2. Message Batching
```go
type BatchProducer struct {
    producer *kafka.Producer
    batch    []*kafka.Message
    batchSize int
    mutex    sync.Mutex
}

func (p *BatchProducer) AddToBatch(msg *kafka.Message) error {
    p.mutex.Lock()
    defer p.mutex.Unlock()

    p.batch = append(p.batch, msg)
    if len(p.batch) >= p.batchSize {
        return p.flush()
    }
    return nil
}

func (p *BatchProducer) flush() error {
    for _, msg := range p.batch {
        err := p.producer.Produce(msg, nil)
        if err != nil {
            return err
        }
    }
    p.batch = p.batch[:0]
    return nil
}
```

### 3. Health Checks
```go
func (p *Producer) IsHealthy() bool {
    // Check if metadata request succeeds
    _, err := p.producer.GetMetadata(nil, true, 1000)
    return err == nil
}

func (c *Consumer) IsHealthy() bool {
    // Check consumer group membership
    _, err := c.consumer.GetMetadata(nil, true, 1000)
    return err == nil
}
```

Remember:
- Always check for errors
- Use proper configuration for your use case
- Implement graceful shutdown
- Monitor consumer lag
- Use batching for better performance
- Implement proper retry mechanisms
- Use Schema Registry for Protobuf messages