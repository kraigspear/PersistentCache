# Cache Clearing Patterns

Discover proven patterns and best practices for effectively managing cache clearing operations in your applications.

## Overview

Effective cache clearing requires understanding when and how to use each clearing option. This guide presents battle-tested patterns that help you optimize performance, manage memory, and maintain data consistency across different application scenarios.

## Common Patterns

### The Memory Pressure Pattern

Use memory-only clearing when the system experiences memory pressure but you want to maintain data availability:

```swift
class MemoryAwareCache {
    private let cache = MemoryCache<String, Data>(identifier: "memory-aware")
    
    init() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryPressure()
            }
        }
    }
    
    private func handleMemoryPressure() async {
        // Free memory but keep data accessible from disk
        await cache.clear(.memoryOnly)
        print("Memory cleared in response to system pressure")
    }
}
```

**When to use:**
- iOS memory warnings
- macOS memory pressure notifications  
- Before performing memory-intensive operations
- When caching large amounts of data (images, documents)

### The Session Cleanup Pattern

Clear memory at session boundaries while preserving long-term data on disk:

```swift
class SessionManager {
    private let userCache = MemoryCache<String, UserData>(identifier: "user-data")
    private let settingsCache = MemoryCache<String, Settings>(identifier: "app-settings")
    
    func startNewSession() async {
        // Clear previous session data from memory
        await userCache.clear(.memoryOnly)
        print("Session memory cleared - disk data preserved for quick access")
    }
    
    func endSession() async {
        // Clear sensitive session data completely
        await userCache.clear(.all)
        // Keep app settings for next session
        await settingsCache.clear(.memoryOnly)
    }
}
```

**When to use:**
- App backgrounding/foregrounding
- User login/logout flows
- Tab switching in multi-user apps
- Between game levels or major UI transitions

### The Storage Management Pattern

Periodically clear disk storage while maintaining active data in memory:

```swift
class StorageManager {
    private let imageCache = MemoryCache<String, Data>(identifier: "images")
    private let cleanupInterval: TimeInterval = 3600 // 1 hour
    
    func schedulePeriodicCleanup() {
        Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performStorageCleanup()
            }
        }
    }
    
    private func performStorageCleanup() async {
        // Keep recently accessed data in memory, clear old disk data
        await imageCache.clear(.diskOnly)
        print("Disk storage cleaned - active data remains in memory")
    }
}
```

**When to use:**
- Scheduled maintenance operations
- When disk space is limited
- For temporary or cached content
- Before major data imports

### The Security-First Pattern

Immediately clear sensitive data from all storage layers:

```swift
class SecureCache {
    private let credentialCache = MemoryCache<String, Credentials>(identifier: "secure-creds")
    private let sessionCache = MemoryCache<String, SessionData>(identifier: "session-data")
    
    func secureLogout() async {
        // Immediately clear all traces of sensitive data
        await credentialCache.clear(.all)
        await sessionCache.clear(.all)
        
        print("All sensitive data securely cleared")
    }
    
    func biometricFailure() async {
        // Clear memory immediately, disk can be cleared later
        await credentialCache.clear(.memoryOnly)
        
        // Schedule disk clearing after delay (user might retry quickly)
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            await credentialCache.clear(.diskOnly)
        }
    }
}
```

**When to use:**
- Authentication failures
- Biometric access denied
- Security policy violations
- App tampering detection

## Advanced Patterns

### The Tiered Clearing Pattern

Clear different cache tiers based on data importance and access patterns:

```swift
class TieredCacheManager {
    private let criticalCache = MemoryCache<String, CriticalData>(identifier: "critical")
    private let standardCache = MemoryCache<String, StandardData>(identifier: "standard")  
    private let temporaryCache = MemoryCache<String, TempData>(identifier: "temporary")
    
    func handleResourceConstraints() async {
        // Clear in order of importance
        await temporaryCache.clear(.all)        // Most expendable
        await standardCache.clear(.memoryOnly)  // Keep on disk
        // Leave critical cache untouched
        
        print("Tiered cleanup completed")
    }
    
    func performFullCleanup() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.temporaryCache.clear(.all) }
            group.addTask { await self.standardCache.clear(.all) }
            group.addTask { await self.criticalCache.clear(.memoryOnly) } // Preserve critical data
        }
    }
}
```

### The Selective Clearing Pattern  

Clear cache based on data age, size, or access patterns:

```swift
class SelectiveCache {
    private let dataCache = MemoryCache<String, TimestampedData>(identifier: "selective")
    private var accessTimes: [String: Date] = [:]
    
    func clearStaleData() async {
        let staleThreshold = Date().addingTimeInterval(-3600) // 1 hour ago
        
        // This pattern works with multiple cache instances
        for (key, accessTime) in accessTimes {
            if accessTime < staleThreshold {
                // Individual item clearing would require additional API
                // For now, we demonstrate the pattern concept
                accessTimes.removeValue(forKey: key)
            }
        }
        
        // Clear disk of potentially stale data, keep recent memory data
        await dataCache.clear(.diskOnly)
        print("Stale data cleared from disk")
    }
    
    func recordAccess(for key: String) {
        accessTimes[key] = Date()
    }
}
```

### The Cascade Clearing Pattern

Clear related caches in a coordinated manner:

```swift
class CascadeCacheManager {
    private let userCache = MemoryCache<String, UserData>(identifier: "users")
    private let avatarCache = MemoryCache<String, Data>(identifier: "avatars")
    private let preferencesCache = MemoryCache<String, Preferences>(identifier: "preferences")
    
    func clearUserData(userId: String, strategy: ClearOption = .all) async {
        // Clear all user-related data in coordination
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.userCache.clear(strategy) }
            group.addTask { await self.avatarCache.clear(strategy) }
            group.addTask { await self.preferencesCache.clear(strategy) }
        }
        
        print("User data cascade cleared with strategy: \(strategy)")
    }
    
    func refreshUserData(userId: String) async {
        // Clear memory to force refresh, keep disk as fallback
        await clearUserData(userId: userId, strategy: .memoryOnly)
        print("User data refresh initiated - disk fallback available")
    }
}
```

## Best Practices

### 1. Match Clearing Strategy to Data Lifecycle

```swift
// Long-lived data: Clear memory during pressure, preserve disk
await appSettingsCache.clear(.memoryOnly)

// Session data: Clear everything on logout
await sessionCache.clear(.all)

// Temporary data: Clear disk regularly, memory as needed  
await downloadCache.clear(.diskOnly)
```

### 2. Coordinate with System Events

```swift
class SystemAwareCache {
    func handleApplicationWillResignActive() async {
        // Clear sensitive memory data when app goes to background
        await sensitiveCache.clear(.memoryOnly)
    }
    
    func handleApplicationWillTerminate() async {
        // Clear all temporary data before shutdown
        await temporaryCache.clear(.all)
    }
}
```

### 3. Use Async Task Groups for Multiple Caches

```swift
func clearMultipleCaches() async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.cache1.clear(.memoryOnly) }
        group.addTask { await self.cache2.clear(.diskOnly) }
        group.addTask { await self.cache3.clear(.all) }
    }
}
```

### 4. Consider Clearing Frequency

```swift
class FrequencyAwareCache {
    private var lastClear: Date = Date()
    private let minimumClearInterval: TimeInterval = 300 // 5 minutes
    
    func clearIfNeeded(_ option: ClearOption) async {
        let now = Date()
        guard now.timeIntervalSince(lastClear) >= minimumClearInterval else {
            return // Too frequent, skip clearing
        }
        
        await cache.clear(option)
        lastClear = now
    }
}
```

### 5. Log Clearing Operations for Debugging

```swift
extension MemoryCache {
    func clearWithLogging(_ option: ClearOption, reason: String) async {
        print("Clearing cache '\(identifier)' with option '\(option)' - Reason: \(reason)")
        await clear(option)
        print("Cache clearing completed")
    }
}
```

## Anti-Patterns to Avoid

### ❌ Excessive Clearing

```swift
// DON'T: Clear cache too frequently
for item in items {
    await cache.clear(.all) // This is wasteful
    await processItem(item)
}
```

```swift
// ✅ DO: Clear once after batch operations
for item in items {
    await processItem(item)
}
await cache.clear(.memoryOnly) // Clear once after processing
```

### ❌ Ignoring Clear Option Context

```swift
// DON'T: Always use .all regardless of context
func handleMemoryWarning() async {
    await cache.clear(.all) // Unnecessarily removes disk data
}
```

```swift
// ✅ DO: Choose appropriate option for context
func handleMemoryWarning() async {
    await cache.clear(.memoryOnly) // Preserves disk data for recovery
}
```

### ❌ Synchronous Clearing Assumptions

```swift
// DON'T: Assume clearing is instantaneous
await cache.clear(.all)
let data = await cache.value(for: key) // Will correctly return nil
```

```swift
// ✅ DO: Understand that clearing is properly awaited
await cache.clear(.memoryOnly)
// Memory is now clear, but disk data remains accessible
```

## See Also

- <doc:ClearingCacheData>
- <doc:CacheClearingScenarios>
- ``ClearOption``
- ``MemoryCache/clear(_:)``