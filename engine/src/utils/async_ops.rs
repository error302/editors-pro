use rayon::ThreadPoolBuilder;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

// ─── Cancellation token ──────────────────────────────────────────────────────

/// A shared cancellation token that can be checked from any thread.
#[derive(Clone)]
pub struct CancellationToken {
    cancelled: Arc<AtomicBool>,
}

impl CancellationToken {
    pub fn new() -> Self {
        Self {
            cancelled: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }

    pub fn reset(&self) {
        self.cancelled.store(false, Ordering::SeqCst);
    }
}

impl Default for CancellationToken {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Task result ─────────────────────────────────────────────────────────────

/// Result from an async task, carrying either success, error, or a progress update.
#[derive(Debug, Clone)]
pub enum TaskResult<T: Clone> {
    Success(T),
    Error(String),
    Progress { percent: f32, message: String },
}

// ─── Progress reporter ───────────────────────────────────────────────────────

/// Trait for reporting progress from long-running operations.
pub trait ProgressReporter: Send + Sync {
    fn report(&self, progress: f32, message: String);
}

/// A simple progress reporter that sends progress via a flume sender.
pub struct ChannelProgressReporter<T: Clone + Send + 'static> {
    sender: flume::Sender<TaskResult<T>>,
}

impl<T: Clone + Send + 'static> ChannelProgressReporter<T> {
    pub fn new(sender: flume::Sender<TaskResult<T>>) -> Self {
        Self { sender }
    }
}

impl<T: Clone + Send + 'static> ProgressReporter for ChannelProgressReporter<T> {
    fn report(&self, progress: f32, message: String) {
        let _ = self.sender.send(TaskResult::Progress {
            percent: progress,
            message,
        });
    }
}

/// A no-op progress reporter that discards all reports.
pub struct NoOpProgressReporter;

impl ProgressReporter for NoOpProgressReporter {
    fn report(&self, _progress: f32, _message: String) {}
}

// ─── Thread pool ─────────────────────────────────────────────────────────────

/// A custom thread pool wrapping rayon's ThreadPool.
pub struct ThreadPool {
    pool: rayon::ThreadPool,
}

impl ThreadPool {
    /// Create a new thread pool with the given number of threads.
    pub fn new(num_threads: usize) -> Result<Self, String> {
        let pool = ThreadPoolBuilder::new()
            .num_threads(num_threads)
            .build()
            .map_err(|e| format!("Failed to create thread pool: {}", e))?;
        Ok(Self { pool })
    }

    /// Create with default thread count (number of CPUs).
    pub fn new_default() -> Result<Self, String> {
        let pool = ThreadPoolBuilder::new()
            .build()
            .map_err(|e| format!("Failed to create thread pool: {}", e))?;
        Ok(Self { pool })
    }

    /// Execute a closure on the thread pool.
    pub fn install<F, R>(&self, f: F) -> R
    where
        F: FnOnce() -> R + Send,
        R: Send,
    {
        self.pool.install(f)
    }

    /// Get the number of threads in the pool.
    pub fn num_threads(&self) -> usize {
        self.pool.current_num_threads()
    }
}

// ─── Async task queue ────────────────────────────────────────────────────────

/// A task queue that allows submitting work and receiving progress/results via channels.
pub struct AsyncTaskQueue<T: Clone + Send + 'static> {
    sender: flume::Sender<TaskResult<T>>,
    receiver: flume::Receiver<TaskResult<T>>,
    thread_pool: ThreadPool,
    cancellation: CancellationToken,
}

impl<T: Clone + Send + 'static> AsyncTaskQueue<T> {
    /// Create a new task queue with default thread pool.
    pub fn new() -> Result<Self, String> {
        let (sender, receiver) = flume::unbounded();
        Ok(Self {
            sender,
            receiver,
            thread_pool: ThreadPool::new_default()?,
            cancellation: CancellationToken::new(),
        })
    }

    /// Create a new task queue with a specific number of threads.
    pub fn with_threads(num_threads: usize) -> Result<Self, String> {
        let (sender, receiver) = flume::unbounded();
        Ok(Self {
            sender,
            receiver,
            thread_pool: ThreadPool::new(num_threads)?,
            cancellation: CancellationToken::new(),
        })
    }

    /// Submit a task to the queue. The closure receives a progress reporter and cancellation token.
    pub fn submit<F>(&self, task: F)
    where
        F: FnOnce(&dyn ProgressReporter, &CancellationToken) -> T + Send + 'static,
    {
        let sender = self.sender.clone();
        let cancellation = self.cancellation.clone();

        self.thread_pool.install(move || {
            let reporter = ChannelProgressReporter::new(sender.clone());
            if cancellation.is_cancelled() {
                let _ = sender.send(TaskResult::Error("Task cancelled before execution".into()));
                return;
            }
            let result = task(&reporter, &cancellation);
            if cancellation.is_cancelled() {
                let _ = sender.send(TaskResult::Error("Task cancelled during execution".into()));
            } else {
                let _ = sender.send(TaskResult::Success(result));
            }
        });
    }

    /// Try to receive a result without blocking.
    pub fn try_recv(&self) -> Option<TaskResult<T>> {
        self.receiver.try_recv().ok()
    }

    /// Block until a result is received.
    pub fn recv(&self) -> TaskResult<T> {
        self.receiver.recv().unwrap_or(TaskResult::Error("Channel disconnected".into()))
    }

    /// Cancel all pending tasks.
    pub fn cancel(&self) {
        self.cancellation.cancel();
    }

    /// Check if cancellation has been requested.
    pub fn is_cancelled(&self) -> bool {
        self.cancellation.is_cancelled()
    }

    /// Reset the cancellation token for reuse.
    pub fn reset_cancellation(&self) {
        self.cancellation.reset();
    }
}

// ─── Unit tests ──────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn test_cancellation_token_new() {
        let token = CancellationToken::new();
        assert!(!token.is_cancelled());
    }

    #[test]
    fn test_cancellation_token_cancel() {
        let token = CancellationToken::new();
        token.cancel();
        assert!(token.is_cancelled());
    }

    #[test]
    fn test_cancellation_token_reset() {
        let token = CancellationToken::new();
        token.cancel();
        assert!(token.is_cancelled());
        token.reset();
        assert!(!token.is_cancelled());
    }

    #[test]
    fn test_cancellation_token_clone() {
        let token = CancellationToken::new();
        let token2 = token.clone();
        token.cancel();
        assert!(token2.is_cancelled());
    }

    #[test]
    fn test_thread_pool_creation() {
        let pool = ThreadPool::new(4);
        assert!(pool.is_ok());
        let pool = pool.unwrap();
        assert_eq!(pool.num_threads(), 4);
    }

    #[test]
    fn test_thread_pool_default() {
        let pool = ThreadPool::new_default();
        assert!(pool.is_ok());
    }

    #[test]
    fn test_thread_pool_install() {
        let pool = ThreadPool::new(2).unwrap();
        let result = pool.install(|| 42);
        assert_eq!(result, 42);
    }

    #[test]
    fn test_async_task_queue_submit() {
        let queue: AsyncTaskQueue<i32> = AsyncTaskQueue::new().unwrap();
        queue.submit(|_reporter, _token| 123);
        // Give the thread pool a moment to execute
        thread::sleep(Duration::from_millis(100));
        let result = queue.try_recv();
        match result {
            Some(TaskResult::Success(v)) => assert_eq!(v, 123),
            _ => panic!("Expected success result"),
        }
    }

    #[test]
    fn test_async_task_queue_cancel() {
        let queue: AsyncTaskQueue<i32> = AsyncTaskQueue::new().unwrap();
        queue.cancel();
        assert!(queue.is_cancelled());
        queue.submit(|_reporter, _token| 42);
        thread::sleep(Duration::from_millis(100));
        let result = queue.try_recv();
        match result {
            Some(TaskResult::Error(_)) => {} // expected
            _ => panic!("Expected error result due to cancellation"),
        }
    }

    #[test]
    fn test_async_task_queue_progress() {
        let queue: AsyncTaskQueue<i32> = AsyncTaskQueue::new().unwrap();
        queue.submit(|reporter, _token| {
            reporter.report(0.5, "Halfway".to_string());
            99
        });
        thread::sleep(Duration::from_millis(200));
        // We should get at least a progress and then a success
        let mut got_progress = false;
        let mut got_success = false;
        while let Some(result) = queue.try_recv() {
            match result {
                TaskResult::Progress { percent, message } => {
                    assert!((percent - 0.5).abs() < 1e-3);
                    assert_eq!(message, "Halfway");
                    got_progress = true;
                }
                TaskResult::Success(v) => {
                    assert_eq!(v, 99);
                    got_success = true;
                }
                TaskResult::Error(_) => panic!("Unexpected error"),
            }
        }
        assert!(got_progress, "Should have received progress");
        assert!(got_success, "Should have received success");
    }

    #[test]
    fn test_no_op_progress_reporter() {
        let reporter = NoOpProgressReporter;
        // Just make sure it doesn't panic
        reporter.report(0.5, "test".to_string());
    }

    #[test]
    fn test_channel_progress_reporter() {
        let (sender, receiver) = flume::unbounded();
        let reporter = ChannelProgressReporter::new(sender);
        reporter.report(0.75, "Progress".to_string());
        let result = receiver.try_recv().unwrap();
        match result {
            TaskResult::Progress { percent, message } => {
                assert!((percent - 0.75).abs() < 1e-3);
                assert_eq!(message, "Progress");
            }
            _ => panic!("Expected progress"),
        }
    }
}
