# ``LRUActorCache``

A thread-safe memory cache with automatic eviction and disk persistence.

## Overview

LRUActorCache provides a high-performance, thread-safe caching solution that combines in-memory storage with persistent disk caching. Built on Swift's actor model and NSCache, it automatically manages memory pressure while ensuring data persistence across app launches.

## Topics

### Cache Management

- ``MemoryCache``
- ``CachedValue``
- ``ClearOption``

### Cache Clearing Operations

- <doc:ClearingCacheData>
- <doc:CacheClearingPatterns>
- <doc:CacheClearingScenarios>

### Getting Started

Use MemoryCache to store and retrieve values with automatic memory management and disk persistence:

```swift
// Create a cache with a unique identifier
let cache = MemoryCache<String, Data>(identifier: "my-cache")

// Store data
await cache.set(imageData, for: "user-avatar")

// Retrieve data
if let cachedData = await cache.value(for: "user-avatar") {
    // Use cached data
}

// Clear cache when needed
await cache.clear(.memoryOnly)  // Clear memory, keep disk
await cache.clear(.diskOnly)    // Clear disk, keep memory  
await cache.clear(.all)         // Clear everything
```