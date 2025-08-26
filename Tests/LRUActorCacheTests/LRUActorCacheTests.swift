import Foundation
import Testing

@testable import LRUActorCache

// A simple CachedValue implementation for testing
private struct TestCachedValue: CachedValue, Equatable {
    let someValue: String

    var data: Data {
        someValue.data(using: .utf8)!
    }

    static func fromData(data: Data) throws -> TestCachedValue {
        guard let someValue = String(data: data, encoding: .utf8) else {
            throw DeserializationError.invalidUTF8
        }
        return TestCachedValue(someValue: someValue)
    }

    enum DeserializationError: Error {
        case invalidUTF8
    }
}

// A CachedValue that can fail deserialization
private struct FailingCachedValue: CachedValue {
    let value: String
    let shouldFailDeserialization: Bool

    var data: Data {
        var result = Data()
        result.append(shouldFailDeserialization ? 1 : 0)
        if let stringData = value.data(using: .utf8) {
            result.append(stringData)
        }
        return result
    }

    static func fromData(data: Data) throws -> FailingCachedValue {
        guard data.count > 0 else {
            throw DeserializationError.invalidData
        }

        let shouldFail = data[0] == 1
        if shouldFail {
            throw DeserializationError.intentionalFailure
        }

        let stringData = data.dropFirst()
        guard let value = String(data: stringData, encoding: .utf8) else {
            throw DeserializationError.invalidString
        }

        return FailingCachedValue(value: value, shouldFailDeserialization: false)
    }

    enum DeserializationError: Error {
        case intentionalFailure
        case invalidData
        case invalidString
    }
}

@Suite("CacheTest", .serialized)
struct CacheTest {
    private let cache: MemoryCache<String, TestCachedValue>

    init() {
        cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")
    }

    @Test("Set and Retrieve Value")
    func setAndRetrieveValue() async throws {
        let key = "testKey"
        let value = TestCachedValue(someValue: "test10")
        await cache.set(value, for: key)
        let retrievedValue = try #require(await cache.value(for: key))
        #expect(retrievedValue == value, "Retrieved value should match the stored value")
    }

    @Test("Contains Key")
    func containsKeys() async {
        await cache.set(TestCachedValue(someValue: "test1"), for: "key1")
        #expect(await cache.contains("key1"), "Cache should contain the key that was just set")
        #expect(await !cache.contains("key2"), "Cache should not contain a key that was never set")
    }

    @Test("Disk Cache Within Same Instance")
    func diskCacheWithinSameInstance() async throws {
        // Test that disk cache works within the same cache instance
        let cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")
        let key = "persistentKey"
        let value = TestCachedValue(someValue: "persistentValue")
        await cache.set(value, for: key)

        // Value should be retrievable
        let retrievedValue = try #require(await cache.value(for: key))
        #expect(retrievedValue == value, "Value should be retrievable from the same cache instance")

        // And should be in memory
        #expect(await cache.contains(key), "Key should exist in memory cache after retrieval")
    }

    @Test("Deserialization Error Handling")
    func deserializationErrorHandling() async throws {
        // Create a cache with failing values
        let cache = MemoryCache<String, FailingCachedValue>(identifier: "test-cache")

        // Store a value that will fail deserialization when loaded from disk
        let key = "failingKey"
        let failingValue = FailingCachedValue(value: "test", shouldFailDeserialization: true)
        await cache.set(failingValue, for: key)

        // Create a new cache instance to force loading from disk
        let cache2 = MemoryCache<String, FailingCachedValue>(identifier: "test-cache")

        // Attempting to retrieve should return nil due to deserialization failure
        let retrievedValue = await cache2.value(for: key)
        #expect(retrievedValue == nil, "Deserialization failure should return nil, not throw")

        // Verify the corrupted file was deleted - a second attempt should also return nil
        // but won't try to load from disk since the file no longer exists
        let cache3 = MemoryCache<String, FailingCachedValue>(identifier: "test-cache")
        let secondAttempt = await cache3.value(for: key)
        #expect(secondAttempt == nil, "Corrupted file should be deleted after first failed attempt")
    }

    @Test("Concurrent Read Operations")
    func concurrentReadOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")
        let key = "concurrentKey"
        let value = TestCachedValue(someValue: "concurrentValue")

        // Set initial value
        await cache.set(value, for: key)

        // Perform multiple concurrent reads
        await withTaskGroup(of: TestCachedValue?.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    await cache.value(for: key)
                }
            }

            // Verify all reads return the same value
            for await result in group {
                #expect(result == value, "All concurrent reads should return the same cached value")
            }
        }
    }

    @Test("Concurrent Write Operations")
    func concurrentWriteOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")

        // Perform multiple concurrent writes to different keys
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask {
                    let key = "key\(i)"
                    let value = TestCachedValue(someValue: "value\(i)")
                    await cache.set(value, for: key)
                }
            }
        }

        // Verify all values were written correctly
        for i in 0 ..< 50 {
            let key = "key\(i)"
            let expectedValue = TestCachedValue(someValue: "value\(i)")
            let retrievedValue = await cache.value(for: key)
            #expect(retrievedValue == expectedValue, "Each concurrent write should be stored correctly")
        }
    }

    @Test("Concurrent Mixed Operations")
    func concurrentMixedOperations() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")

        // Pre-populate some values
        for i in 0 ..< 10 {
            await cache.set(TestCachedValue(someValue: "initial\(i)"), for: "key\(i)")
        }

        // Perform mixed operations concurrently
        await withTaskGroup(of: Void.self) { group in
            // Readers
            for _ in 0 ..< 30 {
                group.addTask {
                    let randomKey = "key\(Int.random(in: 0 ..< 10))"
                    _ = await cache.value(for: randomKey)
                }
            }

            // Writers
            for i in 10 ..< 20 {
                group.addTask {
                    let key = "key\(i)"
                    let value = TestCachedValue(someValue: "new\(i)")
                    await cache.set(value, for: key)
                }
            }

            // Contains checks
            for _ in 0 ..< 20 {
                group.addTask {
                    let randomKey = "key\(Int.random(in: 0 ..< 20))"
                    _ = await cache.contains(randomKey)
                }
            }
        }

        // Verify new values were written
        for i in 10 ..< 20 {
            let key = "key\(i)"
            let expectedValue = TestCachedValue(someValue: "new\(i)")
            let retrievedValue = await cache.value(for: key)
            #expect(retrievedValue == expectedValue, "New values written during concurrent operations should be stored")
        }
    }

    @Test("Concurrent Same Key Updates")
    func concurrentSameKeyUpdates() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "test-cache")
        let key = "raceKey"

        // Multiple tasks updating the same key
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 100 {
                group.addTask {
                    let value = TestCachedValue(someValue: "update\(i)")
                    await cache.set(value, for: key)
                }
            }
        }

        // Verify that some value was set (we can't predict which one due to race conditions)
        let finalValue = await cache.value(for: key)
        #expect(finalValue != nil, "After concurrent updates, some value should be stored")
        #expect(finalValue?.someValue.starts(with: "update") == true, "Stored value should be one of the updates")
    }
}

// MARK: - Data Extension Tests

@Suite("DataCachedValueTests", .serialized)
struct DataCachedValueTests {
    @Test("Data conforms to CachedValue")
    func dataConformsToCachedValue() {
        // Verify Data.data returns self
        let testData = "Hello, World!".data(using: .utf8)!
        #expect(testData.data == testData, "Data.data should return self")

        // Verify Data.fromData returns input unchanged
        let result = try? Data.fromData(data: testData)
        #expect(result == testData, "Data.fromData should return the input unchanged")
    }

    @Test("Store and retrieve Data in MemoryCache")
    func storeAndRetrieveDataInMemoryCache() async throws {
        let cache = MemoryCache<String, Data>(identifier: "test-cache")
        let key = "dataKey"
        let testData = "Test data content".data(using: .utf8)!

        // Store Data
        await cache.set(testData, for: key)

        // Retrieve Data
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == testData, "Retrieved Data should match stored Data")

        // Verify contains
        #expect(await cache.contains(key), "Cache should contain the Data key")
    }

    @Test("Data persistence within same cache instance")
    func dataPersistenceWithinSameCacheInstance() async throws {
        let cache = MemoryCache<String, Data>(identifier: "test-cache")
        let key = "persistentDataKey"
        let testData = "Persistent data".data(using: .utf8)!

        // Store data
        await cache.set(testData, for: key)

        // Retrieve from same instance (should be in memory)
        let fromMemory = await cache.value(for: key)
        #expect(fromMemory == testData, "Data should be retrievable from memory")

        // Verify it's in the cache
        #expect(await cache.contains(key), "Cache should contain the key")

        // Note: Each cache instance has its own disk directory, so data doesn't persist across instances
    }

    @Test("Large Data handling")
    func largeDataHandling() async throws {
        let cache = MemoryCache<String, Data>(identifier: "test-cache")
        let key = "largeDataKey"

        // Create 1MB of data
        let largeData = Data(repeating: 0xFF, count: 1024 * 1024)

        // Store large Data
        await cache.set(largeData, for: key)

        // Retrieve and verify
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == largeData, "Large Data should be stored and retrieved correctly")
        #expect(retrievedData?.count == 1024 * 1024, "Retrieved Data size should match")
    }

    @Test("Empty Data handling")
    func emptyDataHandling() async throws {
        let cache = MemoryCache<String, Data>(identifier: "test-cache")
        let key = "emptyDataKey"
        let emptyData = Data()

        // Store empty Data
        await cache.set(emptyData, for: key)

        // Retrieve and verify
        let retrievedData = await cache.value(for: key)
        #expect(retrievedData == emptyData, "Empty Data should be stored and retrieved")
        #expect(retrievedData?.isEmpty == true, "Retrieved Data should be empty")
    }
}

// MARK: - Disk Persistence Tests

@Suite("DiskPersistenceTests", .serialized)
struct DiskPersistenceTests {
    @Test("Disk persistence across cache instances")
    func diskPersistenceAcrossInstances() async throws {
        let identifier = "persistence-test"
        let key = "persistKey"
        let value = TestCachedValue(someValue: "persisted data")

        // First cache instance - write data
        do {
            let cache1 = MemoryCache<String, TestCachedValue>(identifier: identifier)
            await cache1.set(value, for: key)

            // Verify it's stored
            let retrieved = await cache1.value(for: key)
            #expect(retrieved == value, "Value should be retrievable from first instance")
        }

        // Cache1 is now out of scope, only disk storage remains

        // Second cache instance - should load from disk
        do {
            let cache2 = MemoryCache<String, TestCachedValue>(identifier: identifier)
            let retrieved = await cache2.value(for: key)
            #expect(retrieved == value, "Value should persist across cache instances via disk")
        }
    }

    @Test("Multiple cache instances with same identifier share storage")
    func multipleCachesWithSameIdentifier() async throws {
        let identifier = "shared-storage"
        let cache1 = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let cache2 = MemoryCache<String, TestCachedValue>(identifier: identifier)

        let key = "sharedKey"
        let value = TestCachedValue(someValue: "shared data")

        // Write with cache1
        await cache1.set(value, for: key)

        // Read with cache2 (will read from disk since not in its memory)
        let retrieved = await cache2.value(for: key)
        #expect(retrieved == value, "Cache2 should read cache1's data from shared disk storage")

        // Now cache2 has it in memory too
        #expect(await cache2.contains(key), "Cache2 should have the value in memory after reading from disk")
    }

    @Test("Different identifiers have isolated storage")
    func differentIdentifiersAreIsolated() async throws {
        let cacheA = MemoryCache<String, TestCachedValue>(identifier: "cache-A")
        let cacheB = MemoryCache<String, TestCachedValue>(identifier: "cache-B")

        let key = "sameKey"
        let valueA = TestCachedValue(someValue: "data for A")
        let valueB = TestCachedValue(someValue: "data for B")

        // Set different values with same key
        await cacheA.set(valueA, for: key)
        await cacheB.set(valueB, for: key)

        // Each should have its own value
        let retrievedA = await cacheA.value(for: key)
        let retrievedB = await cacheB.value(for: key)

        #expect(retrievedA == valueA, "Cache A should have its own value")
        #expect(retrievedB == valueB, "Cache B should have its own value")
        #expect(retrievedA != retrievedB, "Different identifiers should not share data")
    }

    @Test("Contains only checks memory, not disk")
    func containsOnlyChecksMemory() async throws {
        let identifier = "memory-check-test"
        let key = "testKey"
        let value = TestCachedValue(someValue: "test data")

        // First instance - write to disk
        do {
            let cache1 = MemoryCache<String, TestCachedValue>(identifier: identifier)
            await cache1.set(value, for: key)
            #expect(await cache1.contains(key), "Should be in memory after set")
        }

        // Second instance - data is on disk but not in memory
        do {
            let cache2 = MemoryCache<String, TestCachedValue>(identifier: identifier)
            #expect(await !cache2.contains(key), "Contains should return false when only on disk")

            // After retrieving, it should be in memory
            let retrieved = await cache2.value(for: key)
            #expect(retrieved != nil, "Value should be retrievable from disk")
            #expect(await cache2.contains(key), "Should be in memory after retrieval")
        }
    }
}

// MARK: - Edge Case Tests

@Suite("EdgeCaseTests", .serialized)
struct EdgeCaseTests {
    @Test("Very long keys are handled correctly")
    func veryLongKeys() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "long-key-test")

        // Create a very long key (1000 characters)
        let longKey = String(repeating: "a", count: 1000)
        let value = TestCachedValue(someValue: "data for long key")

        await cache.set(value, for: longKey)
        let retrieved = await cache.value(for: longKey)

        #expect(retrieved == value, "Very long keys should work correctly")
    }

    @Test("Special characters in cache identifier")
    func specialCharactersInIdentifier() async throws {
        // Test various special characters that might cause issues
        let identifiers = [
            "cache with spaces",
            "cache/with/slashes",
            "cache.with.dots",
            "cache-with-dashes",
            "cache_with_underscores",
            "cache@with@symbols",
            "cache#with#hashes",
        ]

        for identifier in identifiers {
            let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
            let key = "testKey"
            let value = TestCachedValue(someValue: "test data for \(identifier)")

            await cache.set(value, for: key)
            let retrieved = await cache.value(for: key)

            #expect(retrieved == value, "Identifier '\(identifier)' should work correctly")
        }
    }

    @Test("Unicode in keys and identifiers")
    func unicodeSupport() async throws {
        let cache = MemoryCache<String, TestCachedValue>(identifier: "缓存-キャッシュ")

        let unicodeKeys = [
            "🔑",
            "中文键",
            "キー",
            "🇺🇸🇯🇵",
            "مفتاح",
            "κλειδί",
        ]

        for (index, key) in unicodeKeys.enumerated() {
            let value = TestCachedValue(someValue: "data \(index)")
            await cache.set(value, for: key)
            let retrieved = await cache.value(for: key)
            #expect(retrieved == value, "Unicode key '\(key)' should work correctly")
        }
    }

    @Test("Rapid instance creation and destruction")
    func rapidInstanceCreation() async throws {
        let identifier = "rapid-test"
        let key = "testKey"
        let value = TestCachedValue(someValue: "persistent data")

        // Create and destroy many instances rapidly
        for i in 0 ..< 10 {
            let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)

            if i == 0 {
                // First instance sets the value
                await cache.set(value, for: key)
            } else {
                // Subsequent instances should find it on disk
                let retrieved = await cache.value(for: key)
                #expect(retrieved == value, "Instance \(i) should retrieve value from disk")
            }
            // Cache goes out of scope here
        }
    }
}

// MARK: - Clear Method Tests

@Suite("ClearMethodTests", .serialized)
struct ClearMethodTests {
    
    @Test("Clear with memoryOnly option preserves disk data")
    func clearMemoryOnlyPreservesDiskData() async throws {
        // Given: Cache with data in both memory and disk
        let identifier = "memory-only-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let key = "testKey"
        let value = TestCachedValue(someValue: "test data for memory clear")
        
        await cache.set(value, for: key)
        // Verify data is in memory
        #expect(await cache.contains(key), "Data should be in memory after set operation")
        // Verify data can be retrieved (which confirms it's also on disk)
        let retrievedBeforeClear = await cache.value(for: key)
        #expect(retrievedBeforeClear == value, "Data should be retrievable before clearing memory")
        
        // When: Clear memory only
        await cache.clear(.memoryOnly)
        
        // Then: Memory should be cleared but disk should preserve data
        #expect(await !cache.contains(key), "Memory should not contain the key after memory-only clear")
        
        // Data should still be retrievable from disk
        let retrievedAfterClear = await cache.value(for: key)
        #expect(retrievedAfterClear == value, "Data should still be retrievable from disk after memory-only clear")
        
        // After retrieval from disk, it should be back in memory
        #expect(await cache.contains(key), "Key should be in memory again after disk retrieval following clear")
    }
    
    @Test("Clear with diskOnly option preserves memory data")
    func clearDiskOnlyPreservesMemoryData() async throws {
        // Given: Cache with data in both memory and disk
        let identifier = "disk-only-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let key = "testKey"
        let value = TestCachedValue(someValue: "test data for disk clear")
        
        await cache.set(value, for: key)
        // Verify data is in memory
        #expect(await cache.contains(key), "Data should be in memory after set operation")
        
        // When: Clear disk only
        await cache.clear(.diskOnly)
        
        // Then: Memory should still contain the data
        #expect(await cache.contains(key), "Memory should still contain the key after disk-only clear")
        let retrievedFromMemory = await cache.value(for: key)
        #expect(retrievedFromMemory == value, "Data should still be retrievable from memory after disk-only clear")
        
        // Create a new cache instance to verify disk was actually cleared
        let newCache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let retrievedFromDisk = await newCache.value(for: key)
        #expect(retrievedFromDisk == nil, "Data should not be retrievable from disk in new instance after disk-only clear")
    }
    
    @Test("Clear with all option clears both memory and disk")
    func clearAllClearsBothMemoryAndDisk() async throws {
        // Given: Cache with data in both memory and disk
        let identifier = "all-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let key = "testKey"
        let value = TestCachedValue(someValue: "test data for complete clear")
        
        await cache.set(value, for: key)
        // Verify data is in memory
        #expect(await cache.contains(key), "Data should be in memory after set operation")
        
        // When: Clear all
        await cache.clear(.all)
        
        // Then: Memory should be cleared
        #expect(await !cache.contains(key), "Memory should not contain the key after clearing all")
        
        // Data should not be retrievable from current instance
        let retrievedFromSameInstance = await cache.value(for: key)
        #expect(retrievedFromSameInstance == nil, "Data should not be retrievable from same instance after clearing all")
        
        // Create a new cache instance to verify disk was also cleared
        let newCache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let retrievedFromDisk = await newCache.value(for: key)
        #expect(retrievedFromDisk == nil, "Data should not be retrievable from disk in new instance after clearing all")
    }
    
    @Test("Clear with default parameter clears all")
    func clearWithDefaultParameterClearsAll() async throws {
        // Given: Cache with data in both memory and disk
        let identifier = "default-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let key = "testKey"
        let value = TestCachedValue(someValue: "test data for default clear")
        
        await cache.set(value, for: key)
        // Verify data is in memory
        #expect(await cache.contains(key), "Data should be in memory after set operation")
        
        // When: Clear with default parameter (no argument)
        await cache.clear()
        
        // Then: Should behave exactly like clear(.all)
        #expect(await !cache.contains(key), "Memory should not contain the key after default clear")
        
        // Data should not be retrievable from current instance
        let retrievedFromSameInstance = await cache.value(for: key)
        #expect(retrievedFromSameInstance == nil, "Data should not be retrievable from same instance after default clear")
        
        // Create a new cache instance to verify disk was also cleared
        let newCache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        let retrievedFromDisk = await newCache.value(for: key)
        #expect(retrievedFromDisk == nil, "Data should not be retrievable from disk in new instance after default clear")
    }
    
    @Test("Clear memoryOnly does not reset numberOfWrites counter")
    func clearMemoryOnlyDoesNotResetWriteCounter() async throws {
        // Given: Cache with multiple writes to trigger counter tracking
        let identifier = "memory-clear-counter-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        
        // Perform multiple writes to increment the counter
        for i in 0..<50 {
            let key = "key\(i)"
            let value = TestCachedValue(someValue: "value\(i)")
            await cache.set(value, for: key)
        }
        
        // When: Clear memory only
        await cache.clear(.memoryOnly)
        
        // Then: Write one more value and verify cleanup doesn't happen immediately
        // (this is indirect testing since we can't access numberOfWrites directly)
        let testKey = "cleanup-test-key"
        let testValue = TestCachedValue(someValue: "cleanup test")
        await cache.set(testValue, for: testKey)
        
        // The numberOfWrites counter should still be high, so we expect normal behavior
        // We can't directly test the counter, but we can verify the cache still works normally
        let retrieved = await cache.value(for: testKey)
        #expect(retrieved == testValue, "Cache should continue working normally after memory-only clear without counter reset")
    }
    
    @Test("Clear diskOnly and all reset numberOfWrites counter")
    func clearDiskOptionsResetWriteCounter() async throws {
        // Given: Cache with multiple writes to increment counter
        let identifier = "disk-clear-counter-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        
        // Perform multiple writes to increment the counter beyond cleanup threshold
        for i in 0..<120 {
            let key = "counter-key\(i)"
            let value = TestCachedValue(someValue: "counter-value\(i)")
            await cache.set(value, for: key)
        }
        
        // When: Clear disk only
        await cache.clear(.diskOnly)
        
        // Then: The numberOfWrites counter should be reset
        // We test this indirectly by verifying cache continues to work normally
        let testKey = "post-clear-test"
        let testValue = TestCachedValue(someValue: "post clear test")
        await cache.set(testValue, for: testKey)
        
        let retrieved = await cache.value(for: testKey)
        #expect(retrieved == testValue, "Cache should work normally after disk clear with counter reset")
    }
    
    @Test("Multiple clear operations work correctly")
    func multipleClearOperationsWork() async throws {
        // Given: Cache with test data
        let identifier = "multiple-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        
        // Set initial data
        let key1 = "key1"
        let key2 = "key2"
        let value1 = TestCachedValue(someValue: "value1")
        let value2 = TestCachedValue(someValue: "value2")
        
        await cache.set(value1, for: key1)
        await cache.set(value2, for: key2)
        
        // When: Perform multiple clear operations in sequence
        // First clear memory only
        await cache.clear(.memoryOnly)
        #expect(await !cache.contains(key1), "Memory should be cleared after first clear")
        
        // Data should still be on disk
        let fromDisk1 = await cache.value(for: key1)
        #expect(fromDisk1 == value1, "Data should be retrievable from disk after memory clear")
        
        // Clear all
        await cache.clear(.all)
        #expect(await !cache.contains(key1), "Memory should be cleared after second clear")
        
        // Then: Nothing should be retrievable
        let finalResult1 = await cache.value(for: key1)
        let finalResult2 = await cache.value(for: key2)
        #expect(finalResult1 == nil, "No data should remain after clearing all")
        #expect(finalResult2 == nil, "No data should remain after clearing all")
    }
    
    @Test("Clear operations preserve data isolation between cache instances")
    func clearPreservesDataIsolationBetweenInstances() async throws {
        // Given: Two cache instances with different identifiers
        let cacheA = MemoryCache<String, TestCachedValue>(identifier: "cache-isolation-A")
        let cacheB = MemoryCache<String, TestCachedValue>(identifier: "cache-isolation-B")
        
        let key = "shared-key"
        let valueA = TestCachedValue(someValue: "data for cache A")
        let valueB = TestCachedValue(someValue: "data for cache B")
        
        await cacheA.set(valueA, for: key)
        await cacheB.set(valueB, for: key)
        
        // When: Clear all data in cache A
        await cacheA.clear(.all)
        
        // Then: Cache A should have no data
        let resultA = await cacheA.value(for: key)
        #expect(resultA == nil, "Cache A should have no data after clear")
        
        // Cache B should be unaffected
        let resultB = await cacheB.value(for: key)
        #expect(resultB == valueB, "Cache B should retain its data when cache A is cleared")
    }
    
    @Test("Clear handles empty cache gracefully")
    func clearHandlesEmptyCacheGracefully() async throws {
        // Given: Empty cache
        let identifier = "empty-cache-clear-test"
        let cache = MemoryCache<String, TestCachedValue>(identifier: identifier)
        
        // When: Clear operations on empty cache
        await cache.clear(.memoryOnly)
        await cache.clear(.diskOnly)
        await cache.clear(.all)
        await cache.clear() // default
        
        // Then: Operations should complete without error and cache should remain functional
        let testKey = "post-empty-clear-test"
        let testValue = TestCachedValue(someValue: "test after empty clear")
        await cache.set(testValue, for: testKey)
        
        let retrieved = await cache.value(for: testKey)
        #expect(retrieved == testValue, "Cache should remain functional after clearing empty cache")
    }
}
