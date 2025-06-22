# Event Stream System

## Problem Statement

We need an event streaming system with the following requirements:

1. Distribute events to multiple independent consumer tasks
2. Maintain strict event ordering for each consumer
3. Ensure no events are lost, even when some consumers process events slower than others
4. Support throughput of at least 60 messages per second
5. Handle process crashes and ungraceful shutdowns gracefully
6. Allow for potential future enhancements (retry capabilities, etc.)

## Solution: Multiple MPSC Channels with Database Cursor Tracking

### High-Level Architecture

The solution uses multiple tokio MPSC (Multi-Producer, Single-Consumer) channels - one per consumer - combined with database-backed cursor tracking for recovery.

```
                  ┌──────────────┐
                  │  Event Source│
                  └──────┬───────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  Dispatcher  │
                  └─┬───┬───┬───┬┘
                    │   │   │   │
         ┌──────────┘   │   │   └──────────┐
         │              │   │              │
         ▼              ▼   ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Consumer 1   │ │ Consumer 2   │ │ Consumer N   │
│ MPSC Channel │ │ MPSC Channel │ │ MPSC Channel │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Consumer 1   │ │ Consumer 2   │ │ Consumer N   │
│ Processor    │ │ Processor    │ │ Processor    │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └───────┐        │        ┌───────┘
               ▼        ▼        ▼
          ┌─────────────────────────┐
          │   Cursor Tracking Table │
          │   (Unlogged PostgreSQL) │
          └─────────────────────────┘
```

### Detailed Components

#### 1. Event Source
- Ingests events from external systems
- Persists events in a database before dispatching
- Assigns a monotonically increasing sequence number to each event

#### 2. Dispatcher
- After events are persisted, clones events and sends to each consumer channel
- Uses unbounded tokio MPSC channels to prevent backpressure
- Monitors channel health and handles failures

#### 3. Consumer Channels
- One dedicated tokio MPSC channel per consumer
- Unbounded capacity to ensure no events are dropped
- Enables asynchronous processing at each consumer's pace

#### 4. Consumer Processors
- Process events according to their specific logic
- Update cursor position in the database after successful processing
- Designed for independent operation without blocking other consumers

#### 5. Cursor Tracking System
- Unlogged PostgreSQL table to store cursor positions for each consumer
- Schema: `(consumer_id, last_processed_event_id, last_processed_timestamp)`
- Lower overhead than fully logged tables, but still persistent across restarts

### Recovery Mechanism

On system startup:
1. Read the last cursor position for each consumer from the database
2. For each consumer, fetch all events after their last processed event
3. Replay these events to the respective consumer channels
4. Resume normal operation

### Code Structure

```rust
// Event Dispatcher
pub struct EventDispatcher {
    channels: HashMap<ConsumerId, mpsc::Sender<EventData>>,
    db_pool: PgPool,
}

impl EventDispatcher {
    // Register a new consumer
    pub async fn register_consumer(&mut self, consumer_id: ConsumerId) -> mpsc::Receiver<EventData> {
        let (tx, rx) = mpsc::channel(100);  // Initial buffer size, will grow as needed
        self.channels.insert(consumer_id, tx);
        rx
    }
    
    // Dispatch an event to all consumers
    pub async fn dispatch(&self, event: EventData) -> Result<(), Error> {
        // First ensure event is persisted in database
        // ...
        
        // Then dispatch to all channels
        for (consumer_id, channel) in &self.channels {
            let cloned_event = event.clone();
            if let Err(e) = channel.send(cloned_event).await {
                log::error!("Failed to send event to consumer {}: {}", consumer_id, e);
                // Handle channel failure
            }
        }
        Ok(())
    }
    
    // Recovery function called at startup
    pub async fn recover(&self) -> Result<(), Error> {
        // For each consumer, get last processed event ID
        // Fetch all events after that ID
        // Send them to the consumer's channel
        // ...
        Ok(())
    }
}

// Consumer implementation
pub struct Consumer {
    id: ConsumerId,
    db_pool: PgPool,
    receiver: mpsc::Receiver<EventData>,
}

impl Consumer {
    pub async fn run(&mut self) {
        while let Some(event) = self.receiver.recv().await {
            // Process the event
            self.process_event(event).await;
            
            // Update cursor position
            self.update_cursor(event.id).await;
        }
    }
    
    async fn update_cursor(&self, event_id: EventId) {
        // Update the cursor in the unlogged table
        sqlx::query!(
            r#"
            INSERT INTO consumer_cursors (consumer_id, last_event_id, updated_at)
            VALUES ($1, $2, NOW())
            ON CONFLICT (consumer_id) 
            DO UPDATE SET last_event_id = $2, updated_at = NOW()
            "#,
            self.id.as_uuid(),
            event_id.as_uuid()
        )
        .execute(&self.db_pool)
        .await
        .expect("Failed to update cursor");
    }
}
```

### Migration SQL for Cursor Table

```sql
CREATE UNLOGGED TABLE consumer_cursors (
    consumer_id UUID PRIMARY KEY,
    last_event_id UUID NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

-- Index for faster lookups
CREATE INDEX consumer_cursors_updated_at_idx ON consumer_cursors(updated_at);
```

## Trade-offs

### Advantages
1. **No Event Loss**: Events are persisted before processing and never dropped from channels
2. **Independent Processing**: Slow consumers don't block faster ones
3. **Ordering Preserved**: Each consumer processes events in the correct sequence
4. **Crash Recovery**: System can recover after crashes using cursor tracking
5. **Scalability**: Easy to add new consumers without changing the core architecture

### Disadvantages
1. **Memory Usage**: Unbounded channels can consume significant memory if consumers fall far behind
2. **Database Dependency**: Relies on database for both event storage and cursor tracking
3. **Complexity**: More complex than simpler pub/sub models
4. **Latency for Very Slow Consumers**: Extremely slow consumers might face higher latency as their queue grows

## Future Enhancements

1. **Retry Capabilities**: Add logic to retry failed event processing
2. **Channel Monitoring**: Implement metrics and alerting for channel sizes
3. **Backpressure Strategies**: Optional bounded channels with configurable overflow policies
4. **Consumer Groups**: Support for consumer groups where only one consumer in a group processes each event
5. **Distributed Processing**: Extend to multi-process or multi-node architecture if needed