# Real-World Cache Clearing Scenarios

Explore practical scenarios where different cache clearing strategies solve specific application challenges.

## Overview

This guide presents real-world scenarios where cache clearing becomes essential for optimal application performance, user experience, and data management. Each scenario demonstrates when to use `.memoryOnly`, `.diskOnly`, or `.all` clearing options.

## iOS App Scenarios

### Photo Gallery App

A photo gallery app needs to manage large image caches efficiently across different user interactions.

#### Scenario 1: Memory Warning Received

```swift
class PhotoGalleryCache {
    private let thumbnailCache = MemoryCache<String, Data>(identifier: "thumbnails")
    private let fullImageCache = MemoryCache<String, Data>(identifier: "full-images")
    
    func handleMemoryWarning() async {
        // Clear memory but preserve disk for quick reloading
        await thumbnailCache.clear(.memoryOnly)
        await fullImageCache.clear(.memoryOnly)
        
        print("Memory cleared - photos can be quickly reloaded from disk")
    }
}
```

**Why `.memoryOnly`?**
- Immediately frees up memory to prevent app termination
- Preserves expensive-to-download images on disk
- Thumbnails can be quickly regenerated from disk cache
- User experience remains smooth when scrolling resumes

#### Scenario 2: User Clears Storage in Settings

```swift
class PhotoStorageManager {
    private let thumbnailCache = MemoryCache<String, Data>(identifier: "thumbnails")
    private let fullImageCache = MemoryCache<String, Data>(identifier: "full-images")
    
    func clearStorageCache() async {
        // User explicitly wants to free up disk space
        await thumbnailCache.clear(.all)
        await fullImageCache.clear(.all)
        
        // Calculate freed space for UI feedback
        let freedSpace = await calculateFreedSpace()
        print("Cleared \(freedSpace)MB of cached photos")
    }
}
```

**Why `.all`?**
- User explicitly requested storage cleanup
- Removes all traces of cached images
- Frees both memory and disk space
- Images will be re-downloaded as needed

### Social Media App

A social media app manages user feeds, profile images, and temporary content.

#### Scenario 3: User Logs Out

```swift
class SocialMediaCache {
    private let feedCache = MemoryCache<String, FeedData>(identifier: "user-feed")
    private let profileImageCache = MemoryCache<String, Data>(identifier: "profile-images")
    private let draftsCache = MemoryCache<String, DraftPost>(identifier: "drafts")
    
    func handleUserLogout() async {
        // Clear personal data completely
        await feedCache.clear(.all)
        await draftsCache.clear(.all)
        
        // Keep profile images for next user (might be the same person)
        await profileImageCache.clear(.memoryOnly)
        
        print("User data cleared - profile images preserved for quick reloading")
    }
}
```

**Mixed Strategy:**
- `.all` for personal data (feeds, drafts) ensures privacy
- `.memoryOnly` for profile images balances privacy and performance
- Disk-preserved images help if the same user logs back in

#### Scenario 4: App Goes to Background

```swift
class BackgroundCacheManager {
    private let temporaryContentCache = MemoryCache<String, Data>(identifier: "temp-content")
    private let userContentCache = MemoryCache<String, Data>(identifier: "user-content")
    
    func handleAppDidEnterBackground() async {
        // Clear sensitive temporary data from memory only
        await temporaryContentCache.clear(.memoryOnly)
        
        print("Sensitive data cleared from memory - preserved on disk for quick resume")
    }
}
```

**Why `.memoryOnly`?**
- Reduces memory footprint while backgrounded
- Preserves data for quick app resume
- iOS can reclaim memory if needed
- User experience is seamless on foreground return

## macOS App Scenarios

### Document Editor App

A document editor needs to manage document caches, autosave data, and user preferences.

#### Scenario 5: Document Window Closed

```swift
class DocumentCacheManager {
    private let documentCache = MemoryCache<String, DocumentData>(identifier: "documents")
    private let autosaveCache = MemoryCache<String, AutosaveData>(identifier: "autosave")
    
    func handleDocumentClosed(documentId: String) async {
        // This is a conceptual example - actual implementation would need key-specific clearing
        
        // Clear autosave data completely (no longer needed)
        await autosaveCache.clear(.all)
        
        // Clear document from memory but keep recent documents on disk
        await documentCache.clear(.memoryOnly)
        
        print("Document closed - autosave cleared, recent docs preserved")
    }
}
```

**Strategy Rationale:**
- Autosave data is no longer needed after explicit close
- Document data preserved on disk for "Recent Documents" menu
- Memory freed for other documents

#### Scenario 6: System Storage Alert

```swift
class StorageAwareCacheManager {
    private let previewCache = MemoryCache<String, Data>(identifier: "previews")
    private let templateCache = MemoryCache<String, Data>(identifier: "templates")
    
    func handleLowDiskSpace() async {
        // Clear preview cache completely - can be regenerated
        await previewCache.clear(.all)
        
        // Keep templates in memory but clear disk space
        await templateCache.clear(.diskOnly)
        
        print("Disk space freed - templates remain available in current session")
    }
}
```

**Mixed Approach:**
- `.all` for regenerable data (previews) maximizes space savings
- `.diskOnly` for valuable data (templates) maintains session performance

## Web Service Integration Scenarios

### API Response Cache

An app that caches API responses needs to handle different data freshness requirements.

#### Scenario 7: Network Connectivity Changed

```swift
class APIResponseCache {
    private let staticDataCache = MemoryCache<String, StaticData>(identifier: "static-api-data")
    private let dynamicDataCache = MemoryCache<String, DynamicData>(identifier: "dynamic-api-data")
    
    func handleNetworkReconnection() async {
        // Force refresh of dynamic data, keep static data
        await dynamicDataCache.clear(.memoryOnly)
        
        print("Dynamic data cleared from memory - will refresh from server")
        print("Static data preserved for performance")
    }
    
    func handleExtendedOfflinePeriod() async {
        // Keep all data available for offline use
        // Only clear memory under pressure
        await staticDataCache.clear(.memoryOnly)
        await dynamicDataCache.clear(.memoryOnly)
        
        print("Memory cleared - offline data preserved on disk")
    }
}
```

**Context-Aware Strategy:**
- Network available: Clear memory to force fresh data
- Extended offline: Preserve disk data for continued functionality

#### Scenario 8: API Rate Limit Reached

```swift
class RateLimitedCache {
    private let apiCache = MemoryCache<String, APIResponse>(identifier: "api-responses")
    
    func handleRateLimit() async {
        // Preserve all cached data to avoid additional API calls
        // Only clear memory to free up space
        await apiCache.clear(.memoryOnly)
        
        print("Memory cleared - disk cache preserved to avoid API calls during rate limit")
    }
}
```

**Why `.memoryOnly`?**
- Avoids additional API calls that would worsen rate limiting
- Disk cache provides fallback data
- Memory freed for other operations

## Gaming App Scenarios

### Mobile Game Cache Management

A mobile game needs to manage asset caches, user progress, and temporary game data.

#### Scenario 9: Level Transition

```swift
class GameCacheManager {
    private let assetCache = MemoryCache<String, GameAsset>(identifier: "game-assets")
    private let temporaryDataCache = MemoryCache<String, TempGameData>(identifier: "temp-game-data")
    private let progressCache = MemoryCache<String, PlayerProgress>(identifier: "player-progress")
    
    func handleLevelTransition() async {
        // Clear temporary level data completely
        await temporaryDataCache.clear(.all)
        
        // Keep assets in memory for smooth gameplay
        // Clear disk to make room for new level assets
        await assetCache.clear(.diskOnly)
        
        // Ensure progress is saved to disk, clear from memory
        await progressCache.clear(.memoryOnly)
        
        print("Level transition complete - optimized for next level")
    }
}
```

**Coordinated Strategy:**
- `.all` for temporary data that's no longer needed
- `.diskOnly` for assets to free space but maintain performance
- `.memoryOnly` for progress to ensure persistence while freeing memory

#### Scenario 10: Game Pause/Resume

```swift
class GameStateManager {
    private let gameStateCache = MemoryCache<String, GameState>(identifier: "game-state")
    private let uiCache = MemoryCache<String, UIElements>(identifier: "ui-elements")
    
    func handleGamePause() async {
        // Clear memory but preserve everything on disk for quick resume
        await gameStateCache.clear(.memoryOnly)
        await uiCache.clear(.memoryOnly)
        
        print("Game paused - memory cleared, disk preserved for quick resume")
    }
}
```

## E-commerce App Scenarios

### Shopping Cart and Product Cache

An e-commerce app manages product images, user carts, and search results.

#### Scenario 11: Checkout Completion

```swift
class EcommerceCacheManager {
    private let cartCache = MemoryCache<String, ShoppingCart>(identifier: "shopping-cart")
    private let productImageCache = MemoryCache<String, Data>(identifier: "product-images")
    private let searchResultsCache = MemoryCache<String, SearchResults>(identifier: "search-results")
    
    func handleCheckoutComplete() async {
        // Clear cart data completely - no longer needed
        await cartCache.clear(.all)
        
        // Clear old search results, keep product images
        await searchResultsCache.clear(.all)
        await productImageCache.clear(.memoryOnly) // Preserve for browsing
        
        print("Checkout complete - cart cleared, images preserved")
    }
}
```

#### Scenario 12: Product Catalog Update

```swift
class ProductCatalogManager {
    private let catalogCache = MemoryCache<String, ProductCatalog>(identifier: "catalog")
    private let priceCache = MemoryCache<String, PricingData>(identifier: "pricing")
    
    func handleCatalogUpdate() async {
        // Force refresh of all catalog data
        await catalogCache.clear(.memoryOnly)
        await priceCache.clear(.memoryOnly)
        
        print("Catalog update - memory cleared to force fresh data load")
    }
}
```

## Decision Framework

Use this framework to choose the right clearing strategy:

### Use `.memoryOnly` when:
- ✅ System memory pressure
- ✅ Data is expensive to recreate/download
- ✅ Quick app resume is important
- ✅ Disk space is not a concern

### Use `.diskOnly` when:
- ✅ Current session performance is critical
- ✅ Data persistence is not needed
- ✅ Disk space is limited
- ✅ Data is temporary or sensitive

### Use `.all` when:
- ✅ User explicitly requests cleanup
- ✅ Data is no longer relevant
- ✅ Security/privacy is paramount
- ✅ Both memory and disk space are needed

## Performance Impact Analysis

| Clearing Option | Memory Impact | Disk Impact | Next Access Speed | Use Case |
|----------------|---------------|-------------|-------------------|----------|
| `.memoryOnly`  | Immediate ✅   | None ⚪      | Medium (disk read) | Memory pressure |
| `.diskOnly`    | None ⚪        | Immediate ✅ | Fast (memory) | Storage cleanup |
| `.all`         | Immediate ✅   | Immediate ✅ | Slow (network/regenerate) | Complete cleanup |

## See Also

- <doc:ClearingCacheData>
- <doc:CacheClearingPatterns>
- ``ClearOption``
- ``MemoryCache/clear(_:)``