import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/string
import reddit_simulator_gleam/engine_types.{
  type MasterEngineMessage, CreateComment, CreatePost, CreateSubreddit,
  GetComment, GetDirectMessages, GetFeed, GetPost, GetSubreddit,
  GetSubredditComments, GetSubredditPosts, GetSubredditWithMembers, GetUser,
  RegisterUser, SendDirectMessage, SubscribeToSubreddit,
  UnsubscribeFromSubreddit, VoteOnPost,
}
import reddit_simulator_gleam/json_decoder
import reddit_simulator_gleam/json_encoder
import reddit_simulator_gleam/simulation_types.{
  type CommentTree, type DirectMessage, type FeedObject, type Post,
  type Subreddit, type SubredditWithMembers, type User, type VoteType, Downvote,
  Upvote, User as UserType,
}

// REST API Handler Actor
pub type RestApiMessage {
  HttpRequest(
    reply_to: process.Subject(HttpResponse),
    method: String,
    path: String,
    body: String,
  )
}

pub type HttpResponse {
  HttpResponse(status: Int, headers: dict.Dict(String, String), body: String)
}

pub type RestApiState {
  RestApiState(master_engine: process.Subject(MasterEngineMessage))
}

pub fn create_rest_api_handler(
  master_engine: process.Subject(MasterEngineMessage),
) -> Result(process.Subject(RestApiMessage), String) {
  let initial_state = RestApiState(master_engine: master_engine)
  case
    actor.new(initial_state)
    |> actor.on_message(handle_rest_api_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start RestApiHandler: " <> error_to_string(err))
  }
}

fn handle_rest_api_message(
  state: RestApiState,
  message: RestApiMessage,
) -> actor.Next(RestApiState, RestApiMessage) {
  case message {
    HttpRequest(reply_to, method, path, body) -> {
      let response = handle_http_request(state, method, path, body)
      // Send response back to bridge actor
      let _ = process.send(reply_to, response)
      actor.continue(state)
    }
  }
}

fn handle_http_request(
  state: RestApiState,
  method: String,
  path: String,
  body: String,
) -> HttpResponse {
  // Parse path and route
  let path_parts = string.split(path, "/")
  let clean_parts = list.filter(path_parts, fn(p) { p != "" })

  // Route based on method and path
  case method {
    "POST" -> {
      case clean_parts {
        ["users"] -> handle_register_user(state, body)
        ["subreddits"] -> handle_create_subreddit(state, body)
        ["subreddits", subreddit_id, "subscribe"] ->
          handle_subscribe_to_subreddit(state, subreddit_id, body)
        ["subreddits", subreddit_id, "unsubscribe"] ->
          handle_unsubscribe_from_subreddit(state, subreddit_id, body)
        ["posts"] -> handle_create_post(state, body)
        ["posts", post_id, "vote"] -> handle_vote_on_post(state, post_id, body)
        ["comments"] -> handle_create_comment(state, body)
        ["messages"] -> handle_send_direct_message(state, body)
        _ -> create_error_response(404, "Not Found")
      }
    }
    "GET" -> {
      case clean_parts {
        ["users", user_id] -> handle_get_user(state, user_id)
        ["users", user_id, "messages"] ->
          handle_get_direct_messages(state, user_id)
        ["subreddits", subreddit_id] ->
          handle_get_subreddit(state, subreddit_id)
        ["subreddits", subreddit_id, "members"] ->
          handle_get_subreddit_with_members(state, subreddit_id)
        ["subreddits", subreddit_id, "posts"] ->
          handle_get_subreddit_posts(state, subreddit_id)
        ["subreddits", subreddit_id, "comments"] ->
          handle_get_subreddit_comments(state, subreddit_id)
        ["posts", post_id] -> handle_get_post(state, post_id)
        ["comments", comment_id] -> handle_get_comment(state, comment_id)
        ["feed"] -> handle_get_feed(state)
        _ -> create_error_response(404, "Not Found")
      }
    }
    _ -> create_error_response(405, "Method Not Allowed")
  }
}

// User handlers
fn handle_register_user(state: RestApiState, body: String) -> HttpResponse {
  case
    result.all([
      json_decoder.decode_string_field(body, "username"),
      json_decoder.decode_string_field(body, "email"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [username, email] -> {
          let reply = process.new_subject()
          let _ =
            process.send(
              state.master_engine,
              RegisterUser(reply, username, email),
            )
          case process.receive(reply, 5000) {
            Ok(user_id) -> {
              // Parse user_id from "200:user_1" format
              case string.split(user_id, ":") {
                ["200", id] -> {
                  create_json_response(201, "{\"id\":\"" <> id <> "\"}")
                }
                _ -> create_error_response(500, "Invalid response format")
              }
            }
            Error(_) -> create_error_response(500, "Request timeout")
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_get_user(state: RestApiState, user_id: String) -> HttpResponse {
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetUser(reply, user_id))
  case process.receive(reply, 5000) {
    Ok(response) -> {
      // Parse response from "200:user_1" or "404:User not found" format
      case string.split(response, ":") {
        ["200", id] -> {
          let user = UserType(id: id)
          create_json_response(200, json_encoder.encode_user(user))
        }
        ["404", _] -> create_error_response(404, "User not found")
        _ -> create_error_response(500, "Invalid response format")
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

// Subreddit handlers
fn handle_create_subreddit(state: RestApiState, body: String) -> HttpResponse {
  case
    result.all([
      json_decoder.decode_string_field(body, "name"),
      json_decoder.decode_string_field(body, "description"),
      json_decoder.decode_string_field(body, "creatorId"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [name, description, creator_id] -> {
          let reply = process.new_subject()
          let _ =
            process.send(
              state.master_engine,
              CreateSubreddit(reply, name, description, creator_id),
            )
          case process.receive(reply, 5000) {
            Ok(result) -> {
              case result {
                Ok(subreddit) -> {
                  create_json_response(
                    201,
                    json_encoder.encode_subreddit(subreddit),
                  )
                }
                Error(msg) -> create_error_response(400, msg)
              }
            }
            Error(_) -> create_error_response(500, "Request timeout")
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_get_subreddit(
  state: RestApiState,
  subreddit_id: String,
) -> HttpResponse {
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetSubreddit(reply, subreddit_id))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(subreddit) -> {
          create_json_response(200, json_encoder.encode_subreddit(subreddit))
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

fn handle_get_subreddit_with_members(
  state: RestApiState,
  subreddit_id: String,
) -> HttpResponse {
  let reply = process.new_subject()
  let _ =
    process.send(
      state.master_engine,
      GetSubredditWithMembers(reply, subreddit_id),
    )
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(subreddit_with_members) -> {
          create_json_response(
            200,
            json_encoder.encode_subreddit_with_members(subreddit_with_members),
          )
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

fn handle_subscribe_to_subreddit(
  state: RestApiState,
  subreddit_id: String,
  body: String,
) -> HttpResponse {
  case json_decoder.decode_string_field(body, "userId") {
    Ok(user_id) -> {
      let reply = process.new_subject()
      let _ =
        process.send(
          state.master_engine,
          SubscribeToSubreddit(reply, user_id, subreddit_id),
        )
      case process.receive(reply, 5000) {
        Ok(result) -> {
          case result {
            Ok(_) -> create_json_response(200, "{\"success\":true}")
            Error(msg) -> create_error_response(400, msg)
          }
        }
        Error(_) -> create_error_response(500, "Request timeout")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_unsubscribe_from_subreddit(
  state: RestApiState,
  subreddit_id: String,
  body: String,
) -> HttpResponse {
  case json_decoder.decode_string_field(body, "userId") {
    Ok(user_id) -> {
      let reply = process.new_subject()
      let _ =
        process.send(
          state.master_engine,
          UnsubscribeFromSubreddit(reply, user_id, subreddit_id),
        )
      case process.receive(reply, 5000) {
        Ok(result) -> {
          case result {
            Ok(_) -> create_json_response(200, "{\"success\":true}")
            Error(msg) -> create_error_response(400, msg)
          }
        }
        Error(_) -> create_error_response(500, "Request timeout")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

// Post handlers
fn handle_create_post(state: RestApiState, body: String) -> HttpResponse {
  case
    result.all([
      json_decoder.decode_string_field(body, "title"),
      json_decoder.decode_string_field(body, "content"),
      json_decoder.decode_string_field(body, "subredditId"),
      json_decoder.decode_string_field(body, "authorId"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [title, content, subreddit_id, author_id] -> {
          let reply = process.new_subject()
          let _ =
            process.send(
              state.master_engine,
              CreatePost(reply, title, content, author_id, subreddit_id),
            )
          case process.receive(reply, 5000) {
            Ok(result) -> {
              case result {
                Ok(post) -> {
                  create_json_response(201, json_encoder.encode_post(post))
                }
                Error(msg) -> create_error_response(400, msg)
              }
            }
            Error(_) -> create_error_response(500, "Request timeout")
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_get_post(state: RestApiState, post_id: String) -> HttpResponse {
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetPost(reply, post_id))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(post) -> {
          create_json_response(200, json_encoder.encode_post(post))
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

fn handle_get_subreddit_posts(
  state: RestApiState,
  subreddit_id: String,
) -> HttpResponse {
  // Default limit of 25
  let limit = 25
  let reply = process.new_subject()
  let _ =
    process.send(
      state.master_engine,
      GetSubredditPosts(reply, subreddit_id, limit),
    )
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(posts) -> {
          create_json_response(200, json_encoder.encode_list_posts(posts))
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

fn handle_vote_on_post(
  state: RestApiState,
  post_id: String,
  body: String,
) -> HttpResponse {
  case
    result.all([
      json_decoder.decode_string_field(body, "userId"),
      json_decoder.decode_string_field(body, "voteType"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [user_id, vote_type_str] -> {
          case vote_type_str {
            "upvote" -> {
              let vote_type = Upvote
              let reply = process.new_subject()
              let _ =
                process.send(
                  state.master_engine,
                  VoteOnPost(reply, user_id, post_id, vote_type),
                )
              case process.receive(reply, 5000) {
                Ok(result) -> {
                  case result {
                    Ok(_) -> create_json_response(200, "{\"success\":true}")
                    Error(msg) -> create_error_response(400, msg)
                  }
                }
                Error(_) -> create_error_response(500, "Request timeout")
              }
            }
            "downvote" -> {
              let vote_type = Downvote
              let reply = process.new_subject()
              let _ =
                process.send(
                  state.master_engine,
                  VoteOnPost(reply, user_id, post_id, vote_type),
                )
              case process.receive(reply, 5000) {
                Ok(result) -> {
                  case result {
                    Ok(_) -> create_json_response(200, "{\"success\":true}")
                    Error(msg) -> create_error_response(400, msg)
                  }
                }
                Error(_) -> create_error_response(500, "Request timeout")
              }
            }
            _ -> {
              create_error_response(
                400,
                "Invalid voteType. Must be 'upvote' or 'downvote'",
              )
            }
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

// Comment handlers
fn handle_create_comment(state: RestApiState, body: String) -> HttpResponse {
  // Decode required fields first
  case
    result.all([
      json_decoder.decode_string_field(body, "content"),
      json_decoder.decode_string_field(body, "subredditId"),
      json_decoder.decode_string_field(body, "authorId"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [content, subreddit_id, author_id] -> {
          // Decode optional parent comment ID
          let parent_comment_id = case
            json_decoder.decode_optional_string_field(body, "parentCommentId")
          {
            Ok(opt) -> opt
            Error(_) -> option.None
          }
          let reply = process.new_subject()
          let _ =
            process.send(
              state.master_engine,
              CreateComment(
                reply,
                content,
                author_id,
                subreddit_id,
                parent_comment_id,
              ),
            )
          case process.receive(reply, 5000) {
            Ok(result) -> {
              case result {
                Ok(comment) -> {
                  create_json_response(
                    201,
                    json_encoder.encode_comment(comment),
                  )
                }
                Error(msg) -> create_error_response(400, msg)
              }
            }
            Error(_) -> create_error_response(500, "Request timeout")
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_get_comment(state: RestApiState, comment_id: String) -> HttpResponse {
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetComment(reply, comment_id))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(comment) -> {
          create_json_response(200, json_encoder.encode_comment(comment))
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

fn handle_get_subreddit_comments(
  state: RestApiState,
  subreddit_id: String,
) -> HttpResponse {
  let reply = process.new_subject()
  let _ =
    process.send(state.master_engine, GetSubredditComments(reply, subreddit_id))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(comment_tree) -> {
          create_json_response(
            200,
            json_encoder.encode_comment_tree(comment_tree),
          )
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

// Feed handlers
fn handle_get_feed(state: RestApiState) -> HttpResponse {
  let limit = 25
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetFeed(reply, limit))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(feeds) -> {
          create_json_response(
            200,
            json_encoder.encode_list_feed_objects(feeds),
          )
        }
        Error(msg) -> create_error_response(500, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

// Direct message handlers
fn handle_send_direct_message(state: RestApiState, body: String) -> HttpResponse {
  // Try recipientId first, fallback to receiverId for compatibility
  let recipient_id_result = case
    json_decoder.decode_string_field(body, "recipientId")
  {
    Ok(id) -> Ok(id)
    Error(_) -> json_decoder.decode_string_field(body, "receiverId")
  }
  case
    result.all([
      json_decoder.decode_string_field(body, "senderId"),
      recipient_id_result,
      json_decoder.decode_string_field(body, "content"),
    ])
  {
    Ok(fields) -> {
      case fields {
        [sender_id, recipient_id, content] -> {
          let reply = process.new_subject()
          let _ =
            process.send(
              state.master_engine,
              SendDirectMessage(reply, sender_id, recipient_id, content),
            )
          case process.receive(reply, 5000) {
            Ok(result) -> {
              case result {
                Ok(dm) -> {
                  create_json_response(
                    201,
                    json_encoder.encode_direct_message(dm),
                  )
                }
                Error(msg) -> create_error_response(400, msg)
              }
            }
            Error(_) -> create_error_response(500, "Request timeout")
          }
        }
        _ -> create_error_response(400, "Invalid request format")
      }
    }
    Error(msg) -> create_error_response(400, "Invalid request: " <> msg)
  }
}

fn handle_get_direct_messages(
  state: RestApiState,
  user_id: String,
) -> HttpResponse {
  let reply = process.new_subject()
  let _ = process.send(state.master_engine, GetDirectMessages(reply, user_id))
  case process.receive(reply, 5000) {
    Ok(result) -> {
      case result {
        Ok(messages) -> {
          create_json_response(
            200,
            json_encoder.encode_list_direct_messages(messages),
          )
        }
        Error(msg) -> create_error_response(404, msg)
      }
    }
    Error(_) -> create_error_response(500, "Request timeout")
  }
}

// Helper functions
fn create_json_response(status: Int, json_body: String) -> HttpResponse {
  HttpResponse(
    status: status,
    headers: dict.from_list([#("Content-Type", "application/json")]),
    body: json_body,
  )
}

fn create_error_response(status: Int, message: String) -> HttpResponse {
  let error_json = "{\"error\":\"" <> escape_json_string(message) <> "\"}"
  HttpResponse(
    status: status,
    headers: dict.from_list([#("Content-Type", "application/json")]),
    body: error_json,
  )
}

fn escape_json_string(s: String) -> String {
  string.replace(
    string.replace(string.replace(s, "\\", "\\\\"), "\"", "\\\""),
    "\n",
    "\\n",
  )
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
