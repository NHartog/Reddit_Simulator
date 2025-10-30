import gleam/erlang/process
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type MasterEngineMessage, CreateComment, CreatePost, GetDirectMessages,
  GetFeed, SendDirectMessage, SubscribeToSubreddit, UnsubscribeFromSubreddit,
  VoteOnComment, VoteOnPost,
}
import reddit_simulator_gleam/metrics_actor.{
  type MetricsEventType, type MetricsMessage, DM, Post, Read, RecordComplete,
  RecordEnqueue,
}
import reddit_simulator_gleam/simulation_types.{
  type SimulationConfig, type UserAction, type VoteType, CreateCommentAction,
  CreatePostAction, Downvote, GetDirectMessagesAction, GetFeedAction,
  SendDirectMessageAction, SubscribeToSubredditAction,
  UnsubscribeFromSubredditAction, Upvote, VoteOnCommentAction, VoteOnPostAction,
}

// =============================================================================
// FAKE CLIENT ACTOR TYPES
// =============================================================================

pub type FakeClientMessage {
  StartSimulation
  StopSimulation
  ConnectToEngine(engine: process.Subject(MasterEngineMessage))
  ConnectToMetrics(metrics: process.Subject(MetricsMessage))
  PerformAction(action: UserAction)
  Shutdown
}

pub type FakeClientState {
  FakeClientState(
    user_id: String,
    master_engine: Option(process.Subject(MasterEngineMessage)),
    config: SimulationConfig,
    is_running: Bool,
    metrics: Option(process.Subject(MetricsMessage)),
    sim_time_ms: Int,
  )
}

// =============================================================================
// FAKE CLIENT ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_fake_client_actor(
  user_id: String,
  config: SimulationConfig,
) -> Result(process.Subject(FakeClientMessage), String) {
  let initial_state =
    FakeClientState(
      user_id: user_id,
      master_engine: None,
      config: config,
      is_running: False,
      metrics: None,
      sim_time_ms: 0,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_fake_client_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start FakeClientActor: " <> error_to_string(err))
  }
}

fn handle_fake_client_message(
  state: FakeClientState,
  message: FakeClientMessage,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  case message {
    StartSimulation -> {
      io.println("🚀 CLIENT " <> state.user_id <> ": Starting simulation")
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: True,
          metrics: state.metrics,
          sim_time_ms: state.sim_time_ms,
        )
      actor.continue(new_state)
    }

    ConnectToEngine(engine) -> {
      io.println("🔗 CLIENT " <> state.user_id <> ": Connected to master engine")
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: Some(engine),
          config: state.config,
          is_running: state.is_running,
          metrics: state.metrics,
          sim_time_ms: state.sim_time_ms,
        )
      actor.continue(new_state)
    }

    ConnectToMetrics(metrics) -> {
      io.println("📈 CLIENT " <> state.user_id <> ": Connected to metrics")
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: state.is_running,
          metrics: Some(metrics),
          sim_time_ms: state.sim_time_ms,
        )
      actor.continue(new_state)
    }

    StopSimulation -> {
      io.println("⏹️ CLIENT " <> state.user_id <> ": Stopping simulation")
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: False,
          metrics: state.metrics,
          sim_time_ms: state.sim_time_ms,
        )
      actor.continue(new_state)
    }

    PerformAction(action) -> {
      handle_perform_action(state, action)
    }

    Shutdown -> {
      io.println("🔌 CLIENT " <> state.user_id <> ": Shutting down")
      actor.stop()
    }
  }
}

fn handle_perform_action(
  state: FakeClientState,
  action: UserAction,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  case state.master_engine {
    None -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": No master engine connection",
      )
      actor.continue(state)
    }
    Some(engine) -> {
      case action {
        CreatePostAction(title, content, subreddit_id) -> {
          perform_create_post(state, engine, title, content, subreddit_id)
        }
        CreateCommentAction(content, subreddit_id, parent_comment_id) -> {
          perform_create_comment(
            state,
            engine,
            content,
            subreddit_id,
            parent_comment_id,
          )
        }
        VoteOnPostAction(post_id, vote_type) -> {
          perform_vote_on_post(state, engine, post_id, vote_type)
        }
        VoteOnCommentAction(comment_id, vote_type) -> {
          perform_vote_on_comment(state, engine, comment_id, vote_type)
        }
        SendDirectMessageAction(recipient_id, content) -> {
          perform_send_direct_message(state, engine, recipient_id, content)
        }
        SubscribeToSubredditAction(subreddit_id) -> {
          perform_subscribe_to_subreddit(state, engine, subreddit_id)
        }
        UnsubscribeFromSubredditAction(subreddit_id) -> {
          perform_unsubscribe_from_subreddit(state, engine, subreddit_id)
        }
        GetFeedAction -> {
          perform_get_feed(state, engine)
        }
        GetDirectMessagesAction -> {
          perform_get_direct_messages(state, engine)
        }
      }
    }
  }
}

fn perform_create_post(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  title: String,
  content: String,
  subreddit_id: String,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = CreatePost(reply, title, content, state.user_id, subreddit_id)

  io.println("📝 CLIENT " <> state.user_id <> ": Creating post: " <> title)
  // metrics enqueue
  let enqueue_ms = state.sim_time_ms
  send_metrics_enqueue(
    state.metrics,
    Post,
    Some(subreddit_id),
    state.user_id,
    enqueue_ms,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_post)) -> {
      io.println("✅ CLIENT " <> state.user_id <> ": Post created successfully")
      let service_ms = 20
      let complete_ms = enqueue_ms + service_ms
      send_metrics_complete(
        state.metrics,
        Post,
        Some(subreddit_id),
        state.user_id,
        enqueue_ms,
        complete_ms,
      )
      let new_state = FakeClientState(..state, sim_time_ms: complete_ms)
      actor.continue(new_state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Post creation failed: " <> msg,
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Post creation timeout")
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
  }
}

fn perform_create_comment(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  content: String,
  subreddit_id: String,
  parent_comment_id: Option(String),
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message =
    CreateComment(
      reply,
      content,
      state.user_id,
      subreddit_id,
      parent_comment_id,
    )

  io.println("💬 CLIENT " <> state.user_id <> ": Creating comment")
  let enqueue_ms = state.sim_time_ms
  send_metrics_enqueue(
    state.metrics,
    Post,
    Some(subreddit_id),
    state.user_id,
    enqueue_ms,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_comment)) -> {
      io.println(
        "✅ CLIENT " <> state.user_id <> ": Comment created successfully",
      )
      let service_ms = 10
      let complete_ms = enqueue_ms + service_ms
      send_metrics_complete(
        state.metrics,
        Post,
        Some(subreddit_id),
        state.user_id,
        enqueue_ms,
        complete_ms,
      )
      let new_state = FakeClientState(..state, sim_time_ms: complete_ms)
      actor.continue(new_state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Comment creation failed: " <> msg,
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Comment creation timeout")
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
  }
}

fn perform_vote_on_post(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  post_id: String,
  vote_type: VoteType,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = VoteOnPost(reply, state.user_id, post_id, vote_type)

  let vote_str = case vote_type {
    Upvote -> "upvoting"
    Downvote -> "downvoting"
  }
  io.println(
    "👍 CLIENT " <> state.user_id <> ": " <> vote_str <> " post " <> post_id,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      io.println("✅ CLIENT " <> state.user_id <> ": Vote cast successfully")
      actor.continue(state)
    }
    Ok(Error(msg)) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Vote failed: " <> msg)
      actor.continue(state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Vote timeout")
      actor.continue(state)
    }
  }
}

fn perform_vote_on_comment(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  comment_id: String,
  vote_type: VoteType,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = VoteOnComment(reply, state.user_id, comment_id, vote_type)

  let vote_str = case vote_type {
    Upvote -> "upvoting"
    Downvote -> "downvoting"
  }
  io.println(
    "👍 CLIENT "
    <> state.user_id
    <> ": "
    <> vote_str
    <> " comment "
    <> comment_id,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      io.println(
        "✅ CLIENT " <> state.user_id <> ": Comment vote cast successfully",
      )
      actor.continue(state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Comment vote failed: " <> msg,
      )
      actor.continue(state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Comment vote timeout")
      actor.continue(state)
    }
  }
}

fn perform_send_direct_message(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  recipient_id: String,
  content: String,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = SendDirectMessage(reply, state.user_id, recipient_id, content)

  io.println("💌 CLIENT " <> state.user_id <> ": Sending DM to " <> recipient_id)
  let enqueue_ms = state.sim_time_ms
  send_metrics_enqueue(state.metrics, DM, None, state.user_id, enqueue_ms)
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_dm)) -> {
      io.println(
        "✅ CLIENT " <> state.user_id <> ": Direct message sent successfully",
      )
      let service_ms = 8
      let complete_ms = enqueue_ms + service_ms
      send_metrics_complete(
        state.metrics,
        DM,
        None,
        state.user_id,
        enqueue_ms,
        complete_ms,
      )
      let new_state = FakeClientState(..state, sim_time_ms: complete_ms)
      actor.continue(new_state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Direct message failed: " <> msg,
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Direct message timeout")
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
  }
}

fn perform_subscribe_to_subreddit(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  subreddit_id: String,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = SubscribeToSubreddit(reply, state.user_id, subreddit_id)

  io.println(
    "➕ CLIENT "
    <> state.user_id
    <> ": Subscribing to subreddit "
    <> subreddit_id,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      io.println(
        "✅ CLIENT " <> state.user_id <> ": Subscribed to subreddit successfully",
      )
      actor.continue(state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Subscription failed: " <> msg,
      )
      actor.continue(state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Subscription timeout")
      actor.continue(state)
    }
  }
}

fn perform_unsubscribe_from_subreddit(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
  subreddit_id: String,
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = UnsubscribeFromSubreddit(reply, state.user_id, subreddit_id)

  io.println(
    "➖ CLIENT "
    <> state.user_id
    <> ": Unsubscribing from subreddit "
    <> subreddit_id,
  )
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      io.println(
        "✅ CLIENT "
        <> state.user_id
        <> ": Unsubscribed from subreddit successfully",
      )
      actor.continue(state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Unsubscription failed: " <> msg,
      )
      actor.continue(state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Unsubscription timeout")
      actor.continue(state)
    }
  }
}

fn perform_get_feed(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = GetFeed(reply, 10)
  // Get 10 feed items

  io.println("📰 CLIENT " <> state.user_id <> ": Getting feed")
  let enqueue_ms = state.sim_time_ms
  send_metrics_enqueue(state.metrics, Read, None, state.user_id, enqueue_ms)
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_feed)) -> {
      io.println(
        "✅ CLIENT " <> state.user_id <> ": Feed retrieved successfully",
      )
      let service_ms = 5
      let complete_ms = enqueue_ms + service_ms
      send_metrics_complete(
        state.metrics,
        Read,
        None,
        state.user_id,
        enqueue_ms,
        complete_ms,
      )
      let new_state = FakeClientState(..state, sim_time_ms: complete_ms)
      actor.continue(new_state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Feed retrieval failed: " <> msg,
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
    Error(_) -> {
      io.println("❌ CLIENT " <> state.user_id <> ": Feed retrieval timeout")
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
  }
}

fn perform_get_direct_messages(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = GetDirectMessages(reply, state.user_id)

  io.println("📬 CLIENT " <> state.user_id <> ": Getting direct messages")
  let enqueue_ms = state.sim_time_ms
  send_metrics_enqueue(state.metrics, Read, None, state.user_id, enqueue_ms)
  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_messages)) -> {
      io.println(
        "✅ CLIENT "
        <> state.user_id
        <> ": Direct messages retrieved successfully",
      )
      let service_ms = 5
      let complete_ms = enqueue_ms + service_ms
      send_metrics_complete(
        state.metrics,
        Read,
        None,
        state.user_id,
        enqueue_ms,
        complete_ms,
      )
      let new_state = FakeClientState(..state, sim_time_ms: complete_ms)
      actor.continue(new_state)
    }
    Ok(Error(msg)) -> {
      io.println(
        "❌ CLIENT "
        <> state.user_id
        <> ": Direct messages retrieval failed: "
        <> msg,
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
    Error(_) -> {
      io.println(
        "❌ CLIENT " <> state.user_id <> ": Direct messages retrieval timeout",
      )
      let new_state = FakeClientState(..state, sim_time_ms: enqueue_ms + 5)
      actor.continue(new_state)
    }
  }
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

fn send_metrics_enqueue(
  metrics: Option(process.Subject(MetricsMessage)),
  type_: MetricsEventType,
  subreddit: Option(String),
  user_id: String,
  enqueue_ms: Int,
) {
  case metrics {
    None -> #()
    Some(m) -> {
      let _ =
        process.send(m, RecordEnqueue(type_, subreddit, user_id, enqueue_ms))
      #()
    }
  }
}

fn send_metrics_complete(
  metrics: Option(process.Subject(MetricsMessage)),
  type_: MetricsEventType,
  subreddit: Option(String),
  user_id: String,
  enqueue_ms: Int,
  complete_ms: Int,
) {
  case metrics {
    None -> #()
    Some(m) -> {
      let _ =
        process.send(
          m,
          RecordComplete(type_, subreddit, user_id, enqueue_ms, complete_ms),
        )
      #()
    }
  }
}
