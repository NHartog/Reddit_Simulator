import gleam/erlang/process
import gleam/io
import reddit_simulator_gleam/logger_config
import reddit_simulator_gleam/rest_api_server

pub fn main() {
  // Configure logger to suppress actor warnings
  logger_config.configure_logger()

  io.println("Starting REST API server...")
  case rest_api_server.start_rest_api_server(8080) {
    Ok(_) -> {
      io.println("")
      io.println("✓ REST API Server is running on http://localhost:8080")
      io.println("")
      io.println("Available endpoints:")
      io.println("  POST   /users                              - Register user")
      io.println("  GET    /users/{userId}                     - Get user")
      io.println(
        "  POST   /subreddits                         - Create subreddit",
      )
      io.println("  GET    /subreddits/{subredditId}           - Get subreddit")
      io.println(
        "  GET    /subreddits/{subredditId}/members   - Get subreddit with members",
      )
      io.println(
        "  POST   /subreddits/{subredditId}/subscribe - Subscribe to subreddit",
      )
      io.println(
        "  POST   /subreddits/{subredditId}/unsubscribe - Unsubscribe from subreddit",
      )
      io.println(
        "  GET    /subreddits/{subredditId}/posts     - Get subreddit posts",
      )
      io.println("  POST   /posts                              - Create post")
      io.println("  GET    /posts/{postId}                     - Get post")
      io.println("  POST   /posts/{postId}/vote                - Vote on post")
      io.println(
        "  POST   /comments                           - Create comment",
      )
      io.println("  GET    /comments/{commentId}               - Get comment")
      io.println(
        "  GET    /subreddits/{subredditId}/comments  - Get subreddit comments",
      )
      io.println("  GET    /feed                               - Get feed")
      io.println(
        "  POST   /messages                           - Send direct message",
      )
      io.println(
        "  GET    /users/{userId}/messages            - Get direct messages",
      )
      io.println("")
      io.println("Press Ctrl+C to stop the server.")
      io.println("")

      // Keep the process alive
      wait_forever()
    }
    Error(msg) -> {
      io.println("Failed to start server: " <> msg)
    }
  }
}

// Keep process alive
fn wait_forever() -> Nil {
  case process.receive(process.new_subject(), 1000) {
    Ok(_) -> wait_forever()
    Error(_) -> wait_forever()
  }
}
