import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/order
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type FeedActorMessage, type PostActorMessage, type PostActorState,
  type UpvoteActorMessage, FeedAddPost, PostActorState, PostAddSubreddit,
  PostCreatePost, PostGetPost, PostGetSubredditPosts, PostShutdown,
  UpvoteCreateEntry,
}
import reddit_simulator_gleam/metrics_actor.{type MetricsMessage}
import reddit_simulator_gleam/simulation_types.{type Post, Post}

// =============================================================================
// POST ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_post_actor(
  upvote_actor: process.Subject(UpvoteActorMessage),
  feed_actor: process.Subject(FeedActorMessage),
) -> Result(process.Subject(PostActorMessage), String) {
  let initial_state =
    PostActorState(
      posts: dict.new(),
      subreddit_posts: dict.new(),
      next_post_id: 1,
      upvote_actor: upvote_actor,
      feed_actor: feed_actor,
      metrics: option.None,
      queue_len: 0,
      in_flight: 0,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_post_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) -> Error("Failed to start PostActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_post_message(
  state: PostActorState,
  message: PostActorMessage,
) -> actor.Next(PostActorState, PostActorMessage) {
  case message {
    engine_types.PostConnectMetrics(metrics) -> {
      let new_state =
        PostActorState(
          posts: state.posts,
          subreddit_posts: state.subreddit_posts,
          next_post_id: state.next_post_id,
          upvote_actor: state.upvote_actor,
          feed_actor: state.feed_actor,
          metrics: option.Some(metrics),
          queue_len: state.queue_len,
          in_flight: state.in_flight,
        )
      actor.continue(new_state)
    }
    PostCreatePost(reply, title, content, author_id, subreddit_id) -> {
      handle_create_post(state, reply, title, content, author_id, subreddit_id)
    }
    PostGetPost(reply, post_id) -> {
      handle_get_post(state, reply, post_id)
    }
    PostGetSubredditPosts(reply, subreddit_id, limit) -> {
      handle_get_subreddit_posts(state, reply, subreddit_id, limit)
    }
    PostAddSubreddit(reply, subreddit_id) -> {
      handle_add_subreddit(state, reply, subreddit_id)
    }
    PostShutdown -> {
      io.println("PostActor shutting down...")
      actor.stop()
    }
  }
}

// =============================================================================
// POST CREATION
// =============================================================================

fn handle_create_post(
  state: PostActorState,
  reply: process.Subject(Result(Post, String)),
  title: String,
  content: String,
  author_id: String,
  subreddit_id: String,
) -> actor.Next(PostActorState, PostActorMessage) {
  // Check if subreddit exists in our subreddit_posts dictionary
  case dict.get(state.subreddit_posts, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(_) -> {
      // Create new post
      let post_id = "post_" <> int.to_string(state.next_post_id)
      let current_time = 0
      // TODO: Use actual timestamp

      let new_post =
        Post(
          id: post_id,
          title: title,
          content: content,
          author_id: author_id,
          subreddit_id: subreddit_id,
          created_at: current_time,
          score: 0,
          upvotes: 0,
          downvotes: 0,
          comment_count: 0,
        )

      // Add post to state
      let updated_posts = dict.insert(state.posts, post_id, new_post)

      // Add post to subreddit's post list
      case dict.get(state.subreddit_posts, subreddit_id) {
        Error(_) -> {
          // This shouldn't happen if we checked above
          let _ =
            process.send(
              reply,
              Error("Internal error: subreddit posts not found"),
            )
          actor.continue(state)
        }
        Ok(current_posts) -> {
          let updated_subreddit_posts = list.append(current_posts, [post_id])
          let updated_subreddit_posts_dict =
            dict.insert(
              state.subreddit_posts,
              subreddit_id,
              updated_subreddit_posts,
            )

          let updated_state =
            PostActorState(
              posts: updated_posts,
              subreddit_posts: updated_subreddit_posts_dict,
              next_post_id: state.next_post_id + 1,
              upvote_actor: state.upvote_actor,
              feed_actor: state.feed_actor,
              metrics: state.metrics,
              queue_len: state.queue_len,
              in_flight: state.in_flight,
            )

          // Send message to UpvoteActor to create entry for this post
          let upvote_reply = process.new_subject()
          let _ =
            process.send(
              state.upvote_actor,
              UpvoteCreateEntry(upvote_reply, post_id),
            )

          // Send message to FeedActor to add post to feed
          let feed_reply = process.new_subject()
          let _ =
            process.send(
              state.feed_actor,
              FeedAddPost(feed_reply, post_id, title, content),
            )

          io.println(
            "📤 POST ACTOR SENDING: Created post '"
            <> title
            <> "' with ID "
            <> post_id
            <> " in subreddit "
            <> subreddit_id,
          )
          let _ = process.send(reply, Ok(new_post))
          actor.continue(updated_state)
        }
      }
    }
  }
}

// =============================================================================
// POST RETRIEVAL
// =============================================================================

fn handle_get_post(
  state: PostActorState,
  reply: process.Subject(Result(Post, String)),
  post_id: String,
) -> actor.Next(PostActorState, PostActorMessage) {
  case dict.get(state.posts, post_id) {
    Error(_) -> {
      let _ =
        process.send(reply, Error("Post with ID '" <> post_id <> "' not found"))
      actor.continue(state)
    }
    Ok(post) -> {
      io.println(
        "📤 POST ACTOR SENDING: Retrieved post '"
        <> post.title
        <> "' with ID "
        <> post_id,
      )
      let _ = process.send(reply, Ok(post))
      actor.continue(state)
    }
  }
}

// =============================================================================
// SUBREDDIT POSTS RETRIEVAL
// =============================================================================

fn handle_get_subreddit_posts(
  state: PostActorState,
  reply: process.Subject(Result(List(Post), String)),
  subreddit_id: String,
  limit: Int,
) -> actor.Next(PostActorState, PostActorMessage) {
  case dict.get(state.subreddit_posts, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(post_ids) -> {
      // Get posts from post IDs
      let posts = get_posts_from_ids(state.posts, post_ids, limit)
      let post_count = list.length(posts)
      io.println(
        "📤 POST ACTOR SENDING: Retrieved "
        <> int.to_string(post_count)
        <> " posts from subreddit "
        <> subreddit_id,
      )
      let _ = process.send(reply, Ok(posts))
      actor.continue(state)
    }
  }
}

// =============================================================================
// SUBREDDIT ADDITION
// =============================================================================

fn handle_add_subreddit(
  state: PostActorState,
  reply: process.Subject(Result(Nil, String)),
  subreddit_id: String,
) -> actor.Next(PostActorState, PostActorMessage) {
  // Add empty post list for new subreddit
  let updated_subreddit_posts =
    dict.insert(state.subreddit_posts, subreddit_id, [])

  let updated_state =
    PostActorState(
      posts: state.posts,
      subreddit_posts: updated_subreddit_posts,
      next_post_id: state.next_post_id,
      upvote_actor: state.upvote_actor,
      feed_actor: state.feed_actor,
      metrics: state.metrics,
      queue_len: state.queue_len,
      in_flight: state.in_flight,
    )

  io.println(
    "📤 POST ACTOR SENDING: Added subreddit "
    <> subreddit_id
    <> " to post tracking",
  )
  let _ = process.send(reply, Ok(Nil))
  actor.continue(updated_state)
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn get_posts_from_ids(
  posts: dict.Dict(String, Post),
  post_ids: List(String),
  limit: Int,
) -> List(Post) {
  let all_posts =
    list.filter_map(post_ids, fn(post_id) { dict.get(posts, post_id) })
  // Sort by creation time (descending) and limit
  let sorted_posts =
    list.sort(all_posts, fn(a, b) {
      case a.created_at > b.created_at {
        True -> order.Gt
        False ->
          case a.created_at < b.created_at {
            True -> order.Lt
            False -> order.Eq
          }
      }
    })
  list.take(sorted_posts, limit)
}

// =============================================================================
// UPVOTE HANDLING
// =============================================================================

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
