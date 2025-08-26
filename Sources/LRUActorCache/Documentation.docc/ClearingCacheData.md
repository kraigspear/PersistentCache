# Clearing Cache Data

Learn how to efficiently manage cache contents using the clear method with different clearing options.

## Overview

The LRUActorCache provides fine-grained control over cache clearing operations through the `clear(_:)` method and the `ClearOption` enum. This allows you to selectively clear memory, disk, or both storage layers based on your application's needs.

## Clear Options

The `ClearOption` enum provides three distinct clearing strategies:

### Memory Only Clearing

Use `.memoryOnly` to clear only the in-memory cache while preserving disk data:

```swift
let cache = MemoryCache<String, Data>(identifier: "image-cache")

// Store some data
await cache.set(imageData, for: "profile-photo")

// Clear only memory - data remains on disk
await cache.clear(.memoryOnly)

// Data is no longer in memory
let isInMemory = await cache.contains("profile-photo")  // false

// But can still be retrieved from disk
let cachedData = await cache.value(for: "profile-photo")  // Data loaded from disk
```

**Benefits:**
- Frees up memory immediately
- Preserves data for future retrieval
- Useful during memory pressure situations
- Maintains data persistence across app launches

### Disk Only Clearing

Use `.diskOnly` to clear only the disk cache while preserving memory data:

```swift
let cache = MemoryCache<String, Data>(identifier: "temp-cache")

// Store data
await cache.set(temporaryData, for: "temp-file")

// Clear only disk storage
await cache.clear(.diskOnly)

// Data still available in memory
let isInMemory = await cache.contains("temp-file")  // true
let cachedData = await cache.value(for: "temp-file")  // Retrieved from memory

// But won't persist to new cache instances
let newCache = MemoryCache<String, Data>(identifier: "temp-cache")
let persistedData = await newCache.value(for: "temp-file")  // nil
```

**Benefits:**
- Reduces disk space usage
- Maintains current session performance
- Prevents data persistence to future sessions
- Useful for temporary or sensitive data

### Complete Clearing

Use `.all` (or call `clear()` without parameters) to clear both memory and disk:

```swift
let cache = MemoryCache<String, Data>(identifier: "user-cache")

// Store data
await cache.set(userData, for: "user-profile")

// Clear everything
await cache.clear(.all)
// or simply: await cache.clear()

// No data available anywhere
let isInMemory = await cache.contains("user-profile")  // false
let cachedData = await cache.value(for: "user-profile")  // nil

// New instances won't find the data either
let newCache = MemoryCache<String, Data>(identifier: "user-cache")
let persistedData = await newCache.value(for: "user-profile")  // nil
```

**Benefits:**
- Complete cleanup of all cached data
- Frees both memory and disk space
- Ensures no data remnants remain
- Default behavior when no option specified

## Practical Examples

### Clearing Cache During Memory Warnings

```swift
class CacheManager {
    private let imageCache = MemoryCache<String, Data>(identifier: "images")
    private let documentCache = MemoryCache<String, Data>(identifier: "documents")
    
    func handleMemoryWarning() async {
        // Clear memory but keep disk data for quick recovery
        await imageCache.clear(.memoryOnly)
        await documentCache.clear(.memoryOnly)
        
        print("Memory cleared - data can still be retrieved from disk")
    }
}
```

### Clearing Sensitive Data

```swift
class SecurityManager {
    private let tokenCache = MemoryCache<String, Data>(identifier: "auth-tokens")
    
    func logout() async {
        // Remove all traces of sensitive data
        await tokenCache.clear(.all)
        print("All authentication data cleared")
    }
    
    func clearSessionData() async {
        // Clear memory but keep refresh tokens on disk
        await tokenCache.clear(.memoryOnly)
        print("Session cleared, refresh capability maintained")
    }
}
```

### Clearing Temporary Data

```swift
class DownloadManager {
    private let downloadCache = MemoryCache<String, Data>(identifier: "downloads")
    
    func finishDownload(for key: String) async -> Data? {
        let data = await downloadCache.value(for: key)
        
        // Clear disk to prevent accumulation, keep in memory for immediate use
        await downloadCache.clear(.diskOnly)
        
        return data
    }
}
```

## Performance Considerations

### Memory vs Disk Clearing Speed

- **Memory clearing** (`.memoryOnly`) is instantaneous
- **Disk clearing** (`.diskOnly`, `.all`) involves file I/O operations and may take longer
- Clear operations are async and won't block your application

### Impact on Future Operations

- `.memoryOnly`: Next retrieval may be slower (disk read required)
- `.diskOnly`: Current performance maintained, but data won't persist
- `.all`: Complete reset, all future retrievals will return nil

## Error Handling

The clear method handles errors gracefully:

```swift
// Clear operations won't throw errors
await cache.clear(.all)  // Always succeeds

// Individual file deletion errors are logged but don't stop the operation
// The cache remains functional even if some files couldn't be deleted
```

## Thread Safety

All clear operations are fully thread-safe thanks to the actor-based implementation:

```swift
// Multiple concurrent clears are safely handled
await withTaskGroup(of: Void.self) { group in
    group.addTask { await cache.clear(.memoryOnly) }
    group.addTask { await cache.clear(.diskOnly) }
    // The cache ensures operations are properly serialized
}
```

## See Also

- <doc:CacheClearingPatterns>
- <doc:CacheClearingScenarios>
- ``ClearOption``
- ``MemoryCache/clear(_:)``