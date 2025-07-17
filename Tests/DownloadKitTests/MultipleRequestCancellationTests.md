# Multiple Request Cancellation Tests

This test suite provides comprehensive coverage for the `cancel(requests: [DownloadRequest])` method in the ResourceManager class. The tests verify that the method correctly handles arrays, cancels downloads, triggers callbacks, and manages state.

## Test Coverage

### 1. Array Handling Tests

#### `testCancelEmptyArray`
- **Purpose**: Verifies that canceling an empty array doesn't crash or cause issues
- **Verification**: Manager state remains unchanged after canceling empty array
- **Key Assertions**:
  - Current download count remains 0
  - Queued download count remains 0
  - Manager remains active

#### `testCancelSingleRequestArray`
- **Purpose**: Tests canceling a single request using the array method
- **Verification**: Single request is properly canceled with correct callback triggering
- **Key Assertions**:
  - Completion callback is triggered with success: false
  - Download is removed from queues
  - State is properly cleaned up

#### `testCancelMultipleRequestsArray`
- **Purpose**: Tests canceling multiple requests simultaneously
- **Verification**: All requests are canceled and callbacks are triggered
- **Key Assertions**:
  - All 3 requests trigger completion callbacks
  - All downloads are removed from queues
  - State is cleaned up for all requests

#### `testCancelLargeArrayOfRequests`
- **Purpose**: Tests performance and stability with large arrays (50 requests)
- **Verification**: System handles large arrays without issues
- **Key Assertions**:
  - All 50 requests are processed
  - All completion callbacks are triggered
  - Final state shows no remaining downloads

### 2. Callback Triggering Tests

#### `testCancelMultipleRequestsTriggersAllCallbacks`
- **Purpose**: Verifies that multiple callbacks per resource are all triggered
- **Verification**: Thread-safe callback counting and verification
- **Key Assertions**:
  - All 4 callbacks are triggered (2 per resource × 2 resources)
  - Both resources have their callbacks triggered
  - Callback IDs are properly tracked

### 3. State Management Tests

#### `testCancelMultipleRequestsStateManagement`
- **Purpose**: Comprehensive state cleanup verification
- **Verification**: Manager state is properly cleaned after cancellation
- **Key Assertions**:
  - No current downloads remain
  - No queued downloads remain
  - No downloads exist in total
  - Individual request states are cleaned up

#### `testCancelMultipleRequestsProgressTracking`
- **Purpose**: Verifies progress tracking cleanup
- **Verification**: Progress objects are removed after cancellation
- **Key Assertions**:
  - Progress tracking is cleaned up for all requests
  - No progress objects remain after cancellation

### 4. Priority Queue Tests

#### `testCancelMultipleRequestsWithPriorityQueue`
- **Purpose**: Tests cancellation with both normal and priority queues
- **Verification**: Requests are canceled from both queue types
- **Key Assertions**:
  - Downloads are removed from both queues
  - Completion callbacks are triggered
  - State is properly cleaned up

### 5. Error Handling Tests

#### `testCancelRequestArrayWithMixedValidInvalidRequests`
- **Purpose**: Tests robustness with mixed valid/invalid requests
- **Verification**: All requests are handled regardless of validity
- **Key Assertions**:
  - Both valid and invalid requests trigger callbacks
  - No crashes or exceptions occur
  - Mixed array handling is robust

## Test Infrastructure

### Setup Methods
- `setupManager()`: Creates manager with standard download queue
- `setupWithPriorityQueue()`: Creates manager with both normal and priority queues
- Uses in-memory Realm configuration to avoid test conflicts

### Test Utilities
- `ActorCounter`: Thread-safe counter for concurrent callback tracking
- `ActorArray<T>`: Thread-safe array for collecting callback data
- Proper async/await patterns for all operations

## Key Behaviors Verified

1. **Array Handling**: Empty arrays, single requests, multiple requests, and large arrays
2. **Callback Triggering**: All completion callbacks are properly triggered with success: false
3. **State Management**: Downloads removed from queues, progress tracking cleaned up
4. **Priority Queues**: Cancellation works with both normal and priority queues
5. **Error Handling**: Robust handling of mixed valid/invalid requests
6. **Resource Cleanup**: Proper cleanup of internal state and references

## Test Execution

All tests use:
- 2-5 second timeouts for expectations
- Proper async/await patterns
- In-memory Realm configurations
- Thread-safe assertion patterns
- Comprehensive state verification

The tests ensure that the `cancel(requests: [DownloadRequest])` method is robust, reliable, and properly handles all edge cases while maintaining system stability.
