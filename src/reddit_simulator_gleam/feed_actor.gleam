import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type FeedActorMessage, type FeedActorState, FeedActorState, FeedAddPost,
  FeedGetFeed, FeedShutdown,
}
import reddit_simulator_gleam/metrics_actor.{type MetricsMessage}
import reddit_simulator_gleam/simulation_types.{type FeedObject, FeedObject}

// =============================================================================
// FEED ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_feed_actor() -> Result(process.Subject(FeedActorMessage), String) {
  let initial_state =
    FeedActorState(
      feed_posts: dict.new(),
      metrics: option.None,
      queue_len: 0,
      in_flight: 0,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_feed_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) -> Error("Failed to start FeedActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_feed_message(
  state: FeedActorState,
  message: FeedActorMessage,
) -> actor.Next(FeedActorState, FeedActorMessage) {
  case message {
    engine_types.FeedConnectMetrics(metrics) -> {
      let new_state =
        FeedActorState(
          feed_posts: state.feed_posts,
          metrics: option.Some(metrics),
          queue_len: state.queue_len,
          in_flight: state.in_flight,
        )
      actor.continue(new_state)
    }
    FeedAddPost(reply, post_id, title, content) -> {
      handle_add_post(state, reply, post_id, title, content)
    }
    FeedGetFeed(reply, limit) -> {
      handle_get_feed(state, reply, limit)
    }
    FeedShutdown -> {
      actor.stop()
    }
  }
}

// =============================================================================
// POST ADDITION
// =============================================================================

fn handle_add_post(
  state: FeedActorState,
  reply: process.Subject(Result(Nil, String)),
  post_id: String,
  title: String,
  content: String,
) -> actor.Next(FeedActorState, FeedActorMessage) {
  let feed_object = FeedObject(title: title, content: content)
  let updated_feed_posts = dict.insert(state.feed_posts, post_id, feed_object)

  let updated_state =
    FeedActorState(
      feed_posts: updated_feed_posts,
      metrics: state.metrics,
      queue_len: state.queue_len,
      in_flight: state.in_flight,
    )

  let _ = process.send(reply, Ok(Nil))
  actor.continue(updated_state)
}

// =============================================================================
// FEED RETRIEVAL
// =============================================================================

fn handle_get_feed(
  state: FeedActorState,
  reply: process.Subject(Result(List(FeedObject), String)),
  limit: Int,
) -> actor.Next(FeedActorState, FeedActorMessage) {
  let all_feed_objects = dict.values(state.feed_posts)
  let limited_feed = list.take(all_feed_objects, limit)
  let _ = process.send(reply, Ok(limited_feed))
  actor.continue(state)
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
