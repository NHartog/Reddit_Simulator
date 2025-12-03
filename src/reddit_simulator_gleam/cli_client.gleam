import gleam/int
import gleam/io
import gleam/option
import gleam/string
import reddit_simulator_gleam/http_client

pub fn main() {
  io.println("=== Reddit Simulator REST API Client ===")
  io.println("")

  // Initialize HTTP client
  case http_client.start_httpc() {
    Ok(_) -> {
      io.println("HTTP client initialized")
      io.println("")
      run_demo()
    }
    Error(msg) -> {
      io.println("Failed to initialize HTTP client: " <> msg)
    }
  }
}

fn run_demo() {
  let base_url = "http://localhost:8080"
  let timeout = 5000

  io.println("Demo: Testing REST API endpoints")
  io.println("==================================")
  io.println("")

  // 1. Register a user
  io.println("1. Registering a user...")
  case register_user(base_url, "alice", "alice@example.com", timeout) {
    Ok(user_id) -> {
      io.println("   ✓ User registered: " <> user_id)
      io.println("")

      // 2. Create a subreddit
      io.println("2. Creating a subreddit...")
      case
        create_subreddit(
          base_url,
          "programming",
          "Discussion about programming",
          user_id,
          timeout,
        )
      {
        Ok(subreddit_id) -> {
          io.println("   ✓ Subreddit created: " <> subreddit_id)
          io.println("")

          // 3. Create a post
          io.println("3. Creating a post...")
          case
            create_post(
              base_url,
              "Hello World",
              "This is my first post!",
              subreddit_id,
              user_id,
              timeout,
            )
          {
            Ok(post_id) -> {
              io.println("   ✓ Post created: " <> post_id)
              io.println("")

              // 4. Get the post
              io.println("4. Getting the post...")
              case get_post(base_url, post_id, timeout) {
                Ok(_) -> {
                  io.println("   ✓ Post retrieved successfully")
                  io.println("")

                  // 5. Vote on the post
                  io.println("5. Voting on the post...")
                  case
                    vote_on_post(base_url, post_id, user_id, "upvote", timeout)
                  {
                    Ok(_) -> {
                      io.println("   ✓ Vote cast successfully")
                      io.println("")

                      // 6. Create a comment
                      io.println("6. Creating a comment...")
                      case
                        create_comment(
                          base_url,
                          "Great post!",
                          subreddit_id,
                          user_id,
                          option.None,
                          timeout,
                        )
                      {
                        Ok(comment_id) -> {
                          io.println("   ✓ Comment created: " <> comment_id)
                          io.println("")

                          // 7. Get feed
                          io.println("7. Getting feed...")
                          case get_feed(base_url, timeout) {
                            Ok(_) -> {
                              io.println("   ✓ Feed retrieved successfully")
                              io.println("")

                              io.println("Demo completed successfully!")
                            }
                            Error(msg) -> {
                              io.println("   ✗ Failed to get feed: " <> msg)
                            }
                          }
                        }
                        Error(msg) -> {
                          io.println("   ✗ Failed to create comment: " <> msg)
                        }
                      }
                    }
                    Error(msg) -> {
                      io.println("   ✗ Failed to vote: " <> msg)
                    }
                  }
                }
                Error(msg) -> {
                  io.println("   ✗ Failed to get post: " <> msg)
                }
              }
            }
            Error(msg) -> {
              io.println("   ✗ Failed to create post: " <> msg)
            }
          }
        }
        Error(msg) -> {
          io.println("   ✗ Failed to create subreddit: " <> msg)
        }
      }
    }
    Error(msg) -> {
      io.println("   ✗ Failed to register user: " <> msg)
    }
  }
}

// Helper functions for API calls
fn register_user(
  base_url: String,
  username: String,
  email: String,
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/users"
  let body =
    "{\"username\":\"" <> username <> "\",\"email\":\"" <> email <> "\"}"
  case
    http_client.http_post(
      url,
      [#("Content-Type", "application/json")],
      body,
      timeout,
    )
  {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        201 -> {
          // Parse user_id from response: {"id":"user_1"}
          case extract_id_from_json(response_body) {
            Ok(id) -> Ok(id)
            Error(_) -> Error("Failed to parse user ID from response")
          }
        }
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn create_subreddit(
  base_url: String,
  name: String,
  description: String,
  creator_id: String,
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/subreddits"
  let body =
    "{\"name\":\""
    <> name
    <> "\",\"description\":\""
    <> description
    <> "\",\"creatorId\":\""
    <> creator_id
    <> "\"}"
  case
    http_client.http_post(
      url,
      [#("Content-Type", "application/json")],
      body,
      timeout,
    )
  {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        201 -> {
          // Parse subreddit_id from response
          case extract_id_from_json(response_body) {
            Ok(id) -> Ok(id)
            Error(_) -> Error("Failed to parse subreddit ID from response")
          }
        }
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn create_post(
  base_url: String,
  title: String,
  content: String,
  subreddit_id: String,
  author_id: String,
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/posts"
  let body =
    "{\"title\":\""
    <> title
    <> "\",\"content\":\""
    <> content
    <> "\",\"subredditId\":\""
    <> subreddit_id
    <> "\",\"authorId\":\""
    <> author_id
    <> "\"}"
  case
    http_client.http_post(
      url,
      [#("Content-Type", "application/json")],
      body,
      timeout,
    )
  {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        201 -> {
          case extract_id_from_json(response_body) {
            Ok(id) -> Ok(id)
            Error(_) -> Error("Failed to parse post ID from response")
          }
        }
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn get_post(
  base_url: String,
  post_id: String,
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/posts/" <> post_id
  case http_client.http_get(url, timeout) {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        200 -> Ok(response_body)
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn vote_on_post(
  base_url: String,
  post_id: String,
  user_id: String,
  vote_type: String,
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/posts/" <> post_id <> "/vote"
  let body =
    "{\"userId\":\"" <> user_id <> "\",\"voteType\":\"" <> vote_type <> "\"}"
  case
    http_client.http_post(
      url,
      [#("Content-Type", "application/json")],
      body,
      timeout,
    )
  {
    Ok(#(status, _headers, _response_body)) -> {
      case status {
        200 -> Ok("Success")
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn create_comment(
  base_url: String,
  content: String,
  subreddit_id: String,
  author_id: String,
  parent_comment_id: option.Option(String),
  timeout: Int,
) -> Result(String, String) {
  let url = base_url <> "/comments"
  let parent_json = case parent_comment_id {
    option.None -> "null"
    option.Some(id) -> "\"" <> id <> "\""
  }
  let body =
    "{\"content\":\""
    <> content
    <> "\",\"subredditId\":\""
    <> subreddit_id
    <> "\",\"authorId\":\""
    <> author_id
    <> "\",\"parentCommentId\":"
    <> parent_json
    <> "}"
  case
    http_client.http_post(
      url,
      [#("Content-Type", "application/json")],
      body,
      timeout,
    )
  {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        201 -> {
          case extract_id_from_json(response_body) {
            Ok(id) -> Ok(id)
            Error(_) -> Error("Failed to parse comment ID from response")
          }
        }
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn get_feed(base_url: String, timeout: Int) -> Result(String, String) {
  let url = base_url <> "/feed"
  case http_client.http_get(url, timeout) {
    Ok(#(status, _headers, response_body)) -> {
      case status {
        200 -> Ok(response_body)
        _ -> Error("Unexpected status: " <> int.to_string(status))
      }
    }
    Error(msg) -> Error(msg)
  }
}

// Helper to extract ID from JSON response
fn extract_id_from_json(json: String) -> Result(String, String) {
  // Simple extraction: look for "id":"value"
  case string.split(json, "\"id\":\"") {
    [_, rest] -> {
      case string.split(rest, "\"") {
        [id, _] -> Ok(id)
        _ -> Error("Failed to parse ID")
      }
    }
    _ -> Error("ID field not found")
  }
}
