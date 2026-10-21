//! O(1) LRU cache with hit/miss statistics
//!
//! Enhanced version of the basic CacheManager that provides:
//! - O(1) get/put/eviction using an index + doubly-linked list approach
//! - Cache hit/miss ratio tracking
//! - Memory budget enforcement
//! - TTL (time-to-live) support for entries
//! - Memory pressure-aware eviction
//!
//! ## Performance
//!
//! - `get()`: O(1) — hash lookup + list reorder
//! - `put()`: O(1) amortized — hash insert + list push
//! - `evict_lru()`: O(1) — pop from tail
//! - Full eviction scan: O(n) — only when memory budget is exceeded

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

/// A key for the LRU cache
type CacheKey = String;

/// Internal node in the LRU linked list
struct LruNode<V> {
    /// The cached value
    value: V,
    /// Size of the value in bytes
    size: u64,
    /// When this entry was created (for TTL)
    created_at: Instant,
    /// Previous node in the LRU list (most recently used end)
    prev: Option<CacheKey>,
    /// Next node in the LRU list (least recently used end)
    next: Option<CacheKey>,
}

/// Cache statistics
#[derive(Debug, Default)]
pub struct CacheStats {
    /// Number of cache hits
    pub hits: AtomicU64,
    /// Number of cache misses
    pub misses: AtomicU64,
    /// Number of evictions
    pub evictions: AtomicU64,
    /// Total bytes currently stored
    pub used_bytes: AtomicU64,
    /// Peak bytes stored
    pub peak_bytes: AtomicU64,
    /// Current entry count
    pub entry_count: AtomicU64,
}

impl CacheStats {
    /// Get the hit ratio (0.0 to 1.0)
    pub fn hit_ratio(&self) -> f64 {
        let hits = self.hits.load(Ordering::Relaxed);
        let misses = self.misses.load(Ordering::Relaxed);
        let total = hits + misses;
        if total == 0 {
            0.0
        } else {
            hits as f64 / total as f64
        }
    }

    /// Format a summary
    pub fn format_summary(&self) -> String {
        let hits = self.hits.load(Ordering::Relaxed);
        let misses = self.misses.load(Ordering::Relaxed);
        let evictions = self.evictions.load(Ordering::Relaxed);
        let used = self.used_bytes.load(Ordering::Relaxed);
        let entries = self.entry_count.load(Ordering::Relaxed);
        format!(
            "CacheStats: entries={}, {:.1}MB, hits={}, misses={}, hit_rate={:.1}%, evictions={}",
            entries,
            used as f64 / (1024.0 * 1024.0),
            hits,
            misses,
            self.hit_ratio() * 100.0,
            evictions,
        )
    }
}

/// Configuration for the LRU cache
pub struct LruCacheConfig {
    /// Maximum memory budget in bytes
    pub max_bytes: u64,
    /// Default TTL for entries (None = no expiry)
    pub default_ttl: Option<std::time::Duration>,
    /// Whether to track statistics
    pub track_stats: bool,
}

impl Default for LruCacheConfig {
    fn default() -> Self {
        Self {
            max_bytes: 256 * 1024 * 1024, // 256 MB
            default_ttl: None,
            track_stats: true,
        }
    }
}

/// O(1) LRU cache with memory budget enforcement
pub struct LruCache<V: Clone> {
    /// Map from key to LRU node
    entries: HashMap<CacheKey, LruNode<V>>,
    /// Key of the most recently used entry
    mru_key: Option<CacheKey>,
    /// Key of the least recently used entry
    lru_key: Option<CacheKey>,
    /// Configuration
    config: LruCacheConfig,
    /// Cache statistics
    stats: CacheStats,
}

impl<V: Clone> LruCache<V> {
    /// Create a new LRU cache with the given configuration
    pub fn new(config: LruCacheConfig) -> Self {
        Self {
            entries: HashMap::new(),
            mru_key: None,
            lru_key: None,
            config,
            stats: CacheStats::default(),
        }
    }

    /// Create a cache with a memory budget in megabytes
    pub fn with_budget_mb(max_mb: u32) -> Self {
        Self::new(LruCacheConfig {
            max_bytes: (max_mb as u64) * 1024 * 1024,
            ..LruCacheConfig::default()
        })
    }

    /// Get a value from the cache. Returns None on miss.
    /// On hit, the entry is promoted to MRU position.
    pub fn get(&mut self, key: &str) -> Option<V> {
        if let Some(node) = self.entries.get_mut(key) {
            // Check TTL
            if let Some(ttl) = self.config.default_ttl {
                if node.created_at.elapsed() > ttl {
                    // Entry has expired
                    self.remove_entry(key);
                    self.stats.misses.fetch_add(1, Ordering::Relaxed);
                    return None;
                }
            }

            // Promote to MRU
            let key_owned = key.to_string();
            self.promote(&key_owned);
            self.stats.hits.fetch_add(1, Ordering::Relaxed);
            Some(self.entries.get(key)?.value.clone())
        } else {
            self.stats.misses.fetch_add(1, Ordering::Relaxed);
            None
        }
    }

    /// Insert a value into the cache
    pub fn put(&mut self, key: &str, value: V, size_bytes: u64) {
        if size_bytes > self.config.max_bytes {
            return;
        }
        // If key already exists, remove old entry first
        if self.entries.contains_key(key) {
            self.remove_entry(key);
        }

        // Ensure there's enough space
        self.ensure_space(size_bytes);

        // Create the new node
        let node = LruNode {
            value,
            size: size_bytes,
            created_at: Instant::now(),
            prev: self.mru_key.clone(),
            next: None,
        };

        // Update the old MRU's next pointer
        if let Some(mru) = self.mru_key.as_ref() {
            if let Some(old_mru) = self.entries.get_mut(mru) {
                old_mru.next = Some(key.to_string());
            }
        }

        // Insert the node
        self.entries.insert(key.to_string(), node);

        // Update MRU
        self.mru_key = Some(key.to_string());

        // If this is the first entry, it's also the LRU
        if self.lru_key.is_none() {
            self.lru_key = Some(key.to_string());
        }

        // Update stats
        self.stats
            .used_bytes
            .fetch_add(size_bytes, Ordering::Relaxed);
        self.stats.entry_count.fetch_add(1, Ordering::Relaxed);

        let current = self.stats.used_bytes.load(Ordering::Relaxed);
        let peak = self.stats.peak_bytes.load(Ordering::Relaxed);
        if current > peak {
            self.stats.peak_bytes.store(current, Ordering::Relaxed);
        }
    }

    /// Remove a specific entry from the cache
    pub fn remove(&mut self, key: &str) -> Option<V> {
        if self.entries.contains_key(key) {
            let value = self.remove_entry(key);
            value
        } else {
            None
        }
    }

    /// Check if a key exists in the cache (without promoting it)
    pub fn contains(&self, key: &str) -> bool {
        self.entries.contains_key(key)
    }

    /// Get the number of entries in the cache
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Check if the cache is empty
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Get the total bytes used
    pub fn used_bytes(&self) -> u64 {
        self.stats.used_bytes.load(Ordering::Relaxed)
    }

    /// Get the memory budget
    pub fn max_bytes(&self) -> u64 {
        self.config.max_bytes
    }

    /// Get the utilization ratio (0.0 to 1.0)
    pub fn utilization(&self) -> f64 {
        if self.config.max_bytes == 0 {
            0.0
        } else {
            self.used_bytes() as f64 / self.config.max_bytes as f64
        }
    }

    /// Get cache statistics
    pub fn stats(&self) -> &CacheStats {
        &self.stats
    }

    /// Clear all entries from the cache
    pub fn clear(&mut self) {
        let total_bytes: u64 = self.entries.values().map(|n| n.size).sum();
        let count = self.entries.len() as u64;

        self.entries.clear();
        self.mru_key = None;
        self.lru_key = None;

        self.stats
            .used_bytes
            .fetch_sub(total_bytes, Ordering::Relaxed);
        self.stats.entry_count.fetch_sub(count, Ordering::Relaxed);
    }

    /// Evict entries until there's enough space for the given size
    pub fn evict_for_space(&mut self, needed_bytes: u64) {
        self.ensure_space(needed_bytes);
    }

    /// Evict all expired entries
    pub fn evict_expired(&mut self) {
        if self.config.default_ttl.is_none() {
            return;
        }

        let ttl = self.config.default_ttl.unwrap();
        let now = Instant::now();

        // Collect expired keys
        let expired: Vec<CacheKey> = self
            .entries
            .iter()
            .filter(|(_, node)| now.duration_since(node.created_at) > ttl)
            .map(|(key, _)| key.clone())
            .collect();

        for key in expired {
            self.remove_entry(&key);
            self.stats.evictions.fetch_add(1, Ordering::Relaxed);
        }
    }

    // ─── Private methods ─────────────────────────────────────────────────────

    /// Promote an entry to MRU position
    fn promote(&mut self, key: &str) {
        // Already MRU?
        if self.mru_key.as_deref() == Some(key) {
            return;
        }

        // Remove from current position in the list
        self.unlink(key);

        // Insert at MRU position
        if let Some(node) = self.entries.get_mut(key) {
            node.prev = self.mru_key.clone();
            node.next = None;
        }

        // Update old MRU's next
        if let Some(mru) = self.mru_key.as_ref() {
            if let Some(old_mru) = self.entries.get_mut(mru) {
                old_mru.next = Some(key.to_string());
            }
        }

        self.mru_key = Some(key.to_string());
    }

    /// Unlink a node from the doubly-linked list (but don't remove from map)
    fn unlink(&mut self, key: &str) {
        let (prev_key, next_key) = {
            if let Some(node) = self.entries.get(key) {
                (node.prev.clone(), node.next.clone())
            } else {
                return;
            }
        };

        // Update previous node's next
        if let Some(ref prev) = prev_key {
            if let Some(prev_node) = self.entries.get_mut(prev) {
                prev_node.next = next_key.clone();
            }
        }

        // Update next node's prev
        if let Some(ref next) = next_key {
            if let Some(next_node) = self.entries.get_mut(next) {
                next_node.prev = prev_key.clone();
            }
        }

        // Update LRU/MRU pointers
        if self.lru_key.as_deref() == Some(key) {
            self.lru_key = next_key;
        }
        if self.mru_key.as_deref() == Some(key) {
            self.mru_key = prev_key;
        }
    }

    /// Remove an entry and update the linked list
    fn remove_entry(&mut self, key: &str) -> Option<V> {
        if !self.entries.contains_key(key) {
            return None;
        }
        self.unlink(key);
        let node = self.entries.remove(key)?;
        self.stats
            .used_bytes
            .fetch_sub(node.size, Ordering::Relaxed);
        self.stats.entry_count.fetch_sub(1, Ordering::Relaxed);
        Some(node.value)
    }

    /// Evict LRU entries until there's enough space
    fn ensure_space(&mut self, needed: u64) {
        while self.stats.used_bytes.load(Ordering::Relaxed) + needed > self.config.max_bytes {
            if let Some(lru) = self.lru_key.clone() {
                self.remove_entry(&lru);
                self.stats.evictions.fetch_add(1, Ordering::Relaxed);
            } else {
                break; // Cache is empty
            }
        }
    }
}

impl<V: Clone> Default for LruCache<V> {
    fn default() -> Self {
        Self::new(LruCacheConfig::default())
    }
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lru_cache_new() {
        let cache: LruCache<Vec<u8>> = LruCache::with_budget_mb(100);
        assert!(cache.is_empty());
        assert_eq!(cache.len(), 0);
    }

    #[test]
    fn test_lru_cache_put_get() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("key1", vec![1, 2, 3], 3);
        let value = cache.get("key1");
        assert!(value.is_some());
        assert_eq!(value.unwrap(), vec![1, 2, 3]);
    }

    #[test]
    fn test_lru_cache_miss() {
        let mut cache = LruCache::<Vec<u8>>::with_budget_mb(100);
        let value = cache.get("nonexistent");
        assert!(value.is_none());
    }

    #[test]
    fn oversized_entry_preserves_the_existing_cache_and_budget() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 10,
            ..Default::default()
        });
        cache.put("existing", vec![1], 5);
        cache.put("oversized", vec![2], 11);
        assert_eq!(cache.get("existing"), Some(vec![1]));
        assert!(cache.get("oversized").is_none());
        assert!(cache.used_bytes() <= cache.max_bytes());
    }

    #[test]
    fn test_lru_cache_eviction() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 10,
            ..LruCacheConfig::default()
        });
        cache.put("a", vec![1], 5);
        cache.put("b", vec![2], 5);
        // Cache is full (10 bytes). Adding another should evict "a"
        cache.put("c", vec![3], 5);
        assert!(cache.get("a").is_none(), "LRU entry should be evicted");
        assert!(cache.get("b").is_some());
        assert!(cache.get("c").is_some());
    }

    #[test]
    fn test_lru_cache_promote_on_get() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 10,
            ..LruCacheConfig::default()
        });
        cache.put("a", vec![1], 5);
        cache.put("b", vec![2], 5);
        // Access "a" to promote it
        let _ = cache.get("a");
        // Now "b" should be LRU. Adding "c" should evict "b"
        cache.put("c", vec![3], 5);
        assert!(cache.get("a").is_some(), "Promoted entry should remain");
        assert!(cache.get("b").is_none(), "LRU entry should be evicted");
    }

    #[test]
    fn test_lru_cache_remove() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("key1", vec![1, 2, 3], 3);
        let removed = cache.remove("key1");
        assert!(removed.is_some());
        assert!(cache.get("key1").is_none());
    }

    #[test]
    fn test_lru_cache_clear() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        cache.put("b", vec![2], 1);
        cache.clear();
        assert!(cache.is_empty());
        assert_eq!(cache.used_bytes(), 0);
    }

    #[test]
    fn test_lru_cache_stats() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        let _ = cache.get("a"); // hit
        let _ = cache.get("b"); // miss
        let stats = cache.stats();
        assert!(stats.hits.load(Ordering::Relaxed) >= 1);
        assert!(stats.misses.load(Ordering::Relaxed) >= 1);
    }

    #[test]
    fn test_lru_cache_hit_ratio() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        let _ = cache.get("a"); // hit
        let _ = cache.get("a"); // hit
        let _ = cache.get("b"); // miss
        let ratio = cache.stats().hit_ratio();
        assert!(
            (ratio - 0.667).abs() < 0.1,
            "Hit ratio should be ~0.667, got {}",
            ratio
        );
    }

    #[test]
    fn test_lru_cache_utilization() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 1000,
            ..LruCacheConfig::default()
        });
        cache.put("a", vec![1], 500);
        let util = cache.utilization();
        assert!((util - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_lru_cache_contains() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        assert!(cache.contains("a"));
        assert!(!cache.contains("b"));
    }

    #[test]
    fn test_lru_cache_overwrite() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        cache.put("a", vec![2, 3], 2);
        let value = cache.get("a").unwrap();
        assert_eq!(value, vec![2, 3]);
    }

    #[test]
    fn test_lru_cache_stats_summary() {
        let mut cache = LruCache::with_budget_mb(100);
        cache.put("a", vec![1], 1);
        let _ = cache.get("a");
        let summary = cache.stats().format_summary();
        assert!(summary.contains("CacheStats"));
    }

    #[test]
    fn test_lru_cache_many_entries() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 100,
            ..LruCacheConfig::default()
        });
        for i in 0..200 {
            cache.put(&format!("key_{}", i), vec![i as u8], 1);
        }
        // Only 100 entries should fit
        assert!(cache.len() <= 100);
    }

    #[test]
    fn test_lru_cache_evict_for_space() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 100,
            ..LruCacheConfig::default()
        });
        for i in 0..50 {
            cache.put(&format!("key_{}", i), vec![i as u8], 2);
        }
        // Need 50 bytes of space, should evict some entries
        cache.evict_for_space(50);
        let used = cache.used_bytes();
        assert!(used + 50 <= 100);
    }

    #[test]
    fn test_lru_cache_ttl() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 1000,
            default_ttl: Some(std::time::Duration::from_millis(1)),
            track_stats: true,
        });
        cache.put("a", vec![1], 1);
        // Wait for TTL to expire
        std::thread::sleep(std::time::Duration::from_millis(5));
        let value = cache.get("a");
        assert!(value.is_none(), "Entry should have expired");
    }

    #[test]
    fn test_lru_cache_evict_expired() {
        let mut cache = LruCache::new(LruCacheConfig {
            max_bytes: 1000,
            default_ttl: Some(std::time::Duration::from_millis(1)),
            track_stats: true,
        });
        cache.put("a", vec![1], 1);
        cache.put("b", vec![2], 1);
        std::thread::sleep(std::time::Duration::from_millis(5));
        cache.evict_expired();
        assert!(cache.is_empty());
    }
}
