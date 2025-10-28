import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import reddit_simulator_gleam/engine_types.{
  type CommentActorMessage, type CommentActorState, CommentActorState,
  CommentAddSubreddit, CommentCreateComment, CommentGetComment,
  CommentGetSubredditComments, CommentShutdown,
}
import reddit_simulator_gleam/simulation_types.{
  type Comment, type CommentTree, Comment, CommentTree,
}

// =============================================================================
// COMMENT ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_comment_actor() -> Result(
  process.Subject(CommentActorMessage),
  String,
) {
  let initial_state =
    CommentActorState(subreddit_comments: dict.new(), next_comment_id: 1)

  case
    actor.new(initial_state)
    |> actor.on_message(handle_comment_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start CommentActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_comment_message(
  state: CommentActorState,
  message: CommentActorMessage,
) -> actor.Next(CommentActorState, CommentActorMessage) {
  case message {
    CommentCreateComment(
      reply,
      content,
      author_id,
      subreddit_id,
      parent_comment_id,
    ) -> {
      handle_create_comment(
        state,
        reply,
        content,
        author_id,
        subreddit_id,
        parent_comment_id,
      )
    }
    CommentGetComment(reply, comment_id) -> {
      handle_get_comment(state, reply, comment_id)
    }
    CommentGetSubredditComments(reply, subreddit_id) -> {
      handle_get_subreddit_comments(state, reply, subreddit_id)
    }
    CommentAddSubreddit(reply, subreddit_id) -> {
      handle_add_subreddit(state, reply, subreddit_id)
    }
    CommentShutdown -> {
      io.println("CommentActor shutting down...")
      actor.stop()
    }
  }
}

// =============================================================================
// COMMENT CREATION
// =============================================================================

fn handle_create_comment(
  state: CommentActorState,
  reply: process.Subject(Result(Comment, String)),
  content: String,
  author_id: String,
  subreddit_id: String,
  parent_comment_id: Option(String),
) -> actor.Next(CommentActorState, CommentActorMessage) {
  // Check if subreddit exists
  case dict.get(state.subreddit_comments, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(comment_tree) -> {
      // Create new comment
      let comment_id = "comment_" <> int.to_string(state.next_comment_id)
      let current_time = 0
      // TODO: Use actual timestamp

      // Calculate depth based on parent
      let depth = case parent_comment_id {
        None -> 0
        Some(parent_id) -> {
          case dict.get(comment_tree.comments, parent_id) {
            Ok(parent_comment) -> parent_comment.depth + 1
            Error(_) -> 0
            // Fallback if parent not found
          }
        }
      }

      let new_comment =
        Comment(
          id: comment_id,
          content: content,
          author_id: author_id,
          subreddit_id: subreddit_id,
          parent_comment_id: parent_comment_id,
          created_at: current_time,
          score: 0,
          upvotes: 0,
          downvotes: 0,
          depth: depth,
          replies: [],
        )

      // Update comment tree
      let updated_comments =
        dict.insert(comment_tree.comments, comment_id, new_comment)

      // Add to parent's replies if it has a parent
      let final_comments = case parent_comment_id {
        None -> {
          // This is a root comment
          updated_comments
        }
        Some(parent_id) -> {
          case dict.get(updated_comments, parent_id) {
            Ok(parent_comment) -> {
              let updated_parent =
                Comment(
                  id: parent_comment.id,
                  content: parent_comment.content,
                  author_id: parent_comment.author_id,
                  subreddit_id: parent_comment.subreddit_id,
                  parent_comment_id: parent_comment.parent_comment_id,
                  created_at: parent_comment.created_at,
                  score: parent_comment.score,
                  upvotes: parent_comment.upvotes,
                  downvotes: parent_comment.downvotes,
                  depth: parent_comment.depth,
                  replies: list.append(parent_comment.replies, [comment_id]),
                )
              dict.insert(updated_comments, parent_id, updated_parent)
            }
            Error(_) -> updated_comments
          }
        }
      }

      // Update root comments if this is a top-level comment
      let updated_root_comments = case parent_comment_id {
        None -> list.append(comment_tree.root_comments, [comment_id])
        Some(_) -> comment_tree.root_comments
      }

      let updated_comment_tree =
        CommentTree(
          root_comments: updated_root_comments,
          comments: final_comments,
        )

      let updated_state =
        CommentActorState(
          subreddit_comments: dict.insert(
            state.subreddit_comments,
            subreddit_id,
            updated_comment_tree,
          ),
          next_comment_id: state.next_comment_id + 1,
        )

      io.println(
        "📤 COMMENT ACTOR SENDING: Created comment "
        <> comment_id
        <> " in subreddit "
        <> subreddit_id
        <> " by "
        <> author_id,
      )
      let _ = process.send(reply, Ok(new_comment))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// COMMENT RETRIEVAL
// =============================================================================

fn handle_get_comment(
  state: CommentActorState,
  reply: process.Subject(Result(Comment, String)),
  comment_id: String,
) -> actor.Next(CommentActorState, CommentActorMessage) {
  // Search through all subreddits to find the comment
  case find_comment_in_all_subreddits(state, comment_id) {
    None -> {
      let _ =
        process.send(
          reply,
          Error("Comment with ID '" <> comment_id <> "' not found"),
        )
      actor.continue(state)
    }
    Some(comment) -> {
      io.println(
        "📤 COMMENT ACTOR SENDING: Retrieved comment "
        <> comment_id
        <> " by "
        <> comment.author_id,
      )
      let _ = process.send(reply, Ok(comment))
      actor.continue(state)
    }
  }
}

fn handle_get_subreddit_comments(
  state: CommentActorState,
  reply: process.Subject(Result(CommentTree, String)),
  subreddit_id: String,
) -> actor.Next(CommentActorState, CommentActorMessage) {
  case dict.get(state.subreddit_comments, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(comment_tree) -> {
      let comment_count = dict.size(comment_tree.comments)
      let root_count = list.length(comment_tree.root_comments)
      io.println(
        "📤 COMMENT ACTOR SENDING: Retrieved "
        <> int.to_string(comment_count)
        <> " comments for subreddit "
        <> subreddit_id
        <> " ("
        <> int.to_string(root_count)
        <> " root comments)",
      )
      let _ = process.send(reply, Ok(comment_tree))
      actor.continue(state)
    }
  }
}

// =============================================================================
// SUBREDDIT MANAGEMENT
// =============================================================================

fn handle_add_subreddit(
  state: CommentActorState,
  reply: process.Subject(Result(Nil, String)),
  subreddit_id: String,
) -> actor.Next(CommentActorState, CommentActorMessage) {
  // Create empty comment tree for new subreddit
  let empty_comment_tree = CommentTree(root_comments: [], comments: dict.new())

  let updated_state =
    CommentActorState(
      subreddit_comments: dict.insert(
        state.subreddit_comments,
        subreddit_id,
        empty_comment_tree,
      ),
      next_comment_id: state.next_comment_id,
    )

  io.println(
    "📤 COMMENT ACTOR SENDING: Added empty comment tree for subreddit "
    <> subreddit_id,
  )
  let _ = process.send(reply, Ok(Nil))
  actor.continue(updated_state)
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn find_comment_in_all_subreddits(
  state: CommentActorState,
  comment_id: String,
) -> Option(Comment) {
  dict.fold(
    state.subreddit_comments,
    None,
    fn(acc, _subreddit_id, comment_tree) {
      case acc {
        Some(_) -> acc
        None -> {
          case dict.get(comment_tree.comments, comment_id) {
            Ok(comment) -> Some(comment)
            Error(_) -> None
          }
        }
      }
    },
  )
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
