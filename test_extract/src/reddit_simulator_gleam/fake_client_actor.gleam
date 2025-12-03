import gleam/erlang/process
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type MasterEngineMessage, CreateComment, CreatePost, GetDirectMessages,
  GetFeed, SendDirectMessage, SubscribeToSubreddit, UnsubscribeFromSubreddit,
  VoteOnComment, VoteOnPost,
}
import reddit_simulator_gleam/metrics_actor
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
  ConnectToMetrics(metrics: process.Subject(metrics_actor.MetricsMessage))
  PerformAction(action: UserAction)
  Shutdown
}

pub type FakeClientState {
  FakeClientState(
    user_id: String,
    master_engine: Option(process.Subject(MasterEngineMessage)),
    config: SimulationConfig,
    is_running: Bool,
    metrics: Option(process.Subject(metrics_actor.MetricsMessage)),
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
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: True,
          metrics: state.metrics,
        )
      actor.continue(new_state)
    }

    ConnectToEngine(engine) -> {
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: Some(engine),
          config: state.config,
          is_running: state.is_running,
          metrics: state.metrics,
        )
      actor.continue(new_state)
    }

    ConnectToMetrics(metrics) -> {
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: state.is_running,
          metrics: Some(metrics),
        )
      actor.continue(new_state)
    }

    StopSimulation -> {
      let new_state =
        FakeClientState(
          user_id: state.user_id,
          master_engine: state.master_engine,
          config: state.config,
          is_running: False,
          metrics: state.metrics,
        )
      actor.continue(new_state)
    }

    PerformAction(action) -> {
      handle_perform_action(state, action)
    }

    Shutdown -> {
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

  // Metrics enqueue - record actual timestamp
  let enqueue_time_ms = get_time_ms()
  case state.metrics {
    Some(m) -> {
      let _ =
        process.send(
          m,
          metrics_actor.RecordEnqueue(
            metrics_actor.Post,
            Some(subreddit_id),
            state.user_id,
            enqueue_time_ms,
          ),
        )
      #()
    }
    None -> #()
  }

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_post)) -> {
      // Metrics complete - record actual timestamp and calculate latency
      let complete_time_ms = get_time_ms()
      case state.metrics {
        Some(m) -> {
          let _ =
            process.send(
              m,
              metrics_actor.RecordComplete(
                metrics_actor.Post,
                Some(subreddit_id),
                state.user_id,
                enqueue_time_ms,
                complete_time_ms,
              ),
            )
          #()
        }
        None -> #()
      }
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
      actor.continue(state)
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_comment)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
      actor.continue(state)
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_dm)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
      actor.continue(state)
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
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

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
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
  // Metrics enqueue for read - record actual timestamp
  let enqueue_time_ms = get_time_ms()
  case state.metrics {
    Some(m) -> {
      let _ =
        process.send(
          m,
          metrics_actor.RecordEnqueue(
            metrics_actor.Read,
            None,
            state.user_id,
            enqueue_time_ms,
          ),
        )
      #()
    }
    None -> #()
  }

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_feed)) -> {
      // Metrics complete - record actual timestamp and calculate latency
      let complete_time_ms = get_time_ms()
      case state.metrics {
        Some(m) -> {
          let _ =
            process.send(
              m,
              metrics_actor.RecordComplete(
                metrics_actor.Read,
                None,
                state.user_id,
                enqueue_time_ms,
                complete_time_ms,
              ),
            )
          #()
        }
        None -> #()
      }
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
      actor.continue(state)
    }
  }
}

fn perform_get_direct_messages(
  state: FakeClientState,
  engine: process.Subject(MasterEngineMessage),
) -> actor.Next(FakeClientState, FakeClientMessage) {
  let reply = process.new_subject()
  let message = GetDirectMessages(reply, state.user_id)

  let _ = process.send(engine, message)

  case process.receive(reply, 5000) {
    Ok(Ok(_messages)) -> {
      actor.continue(state)
    }
    Ok(Error(_msg)) -> {
      actor.continue(state)
    }
    Error(_) -> {
      actor.continue(state)
    }
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Get current time in milliseconds using Erlang's monotonic time
// erlang:monotonic_time() returns nanoseconds, so we divide by 1,000,000
fn get_time_ms() -> Int {
  let ns = erlang_monotonic_time_ns()
  ns / 1_000_000
}

@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time_ns() -> Int

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
