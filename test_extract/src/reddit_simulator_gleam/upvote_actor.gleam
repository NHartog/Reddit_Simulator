import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type UpvoteActorMessage, type UpvoteActorState, UpvoteActorState,
  UpvoteCreateEntry, UpvoteDownvote, UpvoteGetUpvote, UpvoteShutdown,
  UpvoteUpvote,
}
import reddit_simulator_gleam/simulation_types.{type UpvoteData, UpvoteData}

// =============================================================================
// UPVOTE ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_upvote_actor() -> Result(
  process.Subject(UpvoteActorMessage),
  String,
) {
  let initial_state = UpvoteActorState(upvotes: dict.new())

  case
    actor.new(initial_state)
    |> actor.on_message(handle_upvote_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) -> Error("Failed to start UpvoteActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_upvote_message(
  state: UpvoteActorState,
  message: UpvoteActorMessage,
) -> actor.Next(UpvoteActorState, UpvoteActorMessage) {
  case message {
    UpvoteCreateEntry(reply, post_id) -> {
      handle_create_entry(state, reply, post_id)
    }
    UpvoteUpvote(reply, post_id) -> {
      handle_upvote(state, reply, post_id)
    }
    UpvoteDownvote(reply, post_id) -> {
      handle_downvote(state, reply, post_id)
    }
    UpvoteGetUpvote(reply, post_id) -> {
      handle_get_upvote(state, reply, post_id)
    }
    UpvoteShutdown -> {
      actor.stop()
    }
  }
}

// =============================================================================
// UPVOTE ENTRY CREATION
// =============================================================================

fn handle_create_entry(
  state: UpvoteActorState,
  reply: process.Subject(Result(Nil, String)),
  post_id: String,
) -> actor.Next(UpvoteActorState, UpvoteActorMessage) {
  // Check if entry already exists
  case dict.get(state.upvotes, post_id) {
    Ok(_) -> {
      // Entry already exists, just acknowledge
      let _ = process.send(reply, Ok(Nil))
      actor.continue(state)
    }
    Error(_) -> {
      // Create new upvote entry
      let new_upvote = UpvoteData(upvotes: 0, downvotes: 0, karma: 0)
      let updated_upvotes = dict.insert(state.upvotes, post_id, new_upvote)
      let updated_state = UpvoteActorState(upvotes: updated_upvotes)

      let _ = process.send(reply, Ok(Nil))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// UPVOTE HANDLING
// =============================================================================

fn handle_upvote(
  state: UpvoteActorState,
  reply: process.Subject(Result(UpvoteData, String)),
  post_id: String,
) -> actor.Next(UpvoteActorState, UpvoteActorMessage) {
  case dict.get(state.upvotes, post_id) {
    Error(_) -> {
      let _ =
        process.send(reply, Error("Post with ID '" <> post_id <> "' not found"))
      actor.continue(state)
    }
    Ok(upvote) -> {
      let updated_upvote =
        UpvoteData(
          upvotes: upvote.upvotes + 1,
          downvotes: upvote.downvotes,
          karma: upvote.upvotes + 1 - upvote.downvotes,
        )
      let updated_upvotes = dict.insert(state.upvotes, post_id, updated_upvote)
      let updated_state = UpvoteActorState(upvotes: updated_upvotes)
      let _ = process.send(reply, Ok(updated_upvote))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// DOWNVOTE HANDLING
// =============================================================================

fn handle_downvote(
  state: UpvoteActorState,
  reply: process.Subject(Result(UpvoteData, String)),
  post_id: String,
) -> actor.Next(UpvoteActorState, UpvoteActorMessage) {
  case dict.get(state.upvotes, post_id) {
    Error(_) -> {
      let _ =
        process.send(reply, Error("Post with ID '" <> post_id <> "' not found"))
      actor.continue(state)
    }
    Ok(upvote) -> {
      let updated_upvote =
        UpvoteData(
          upvotes: upvote.upvotes,
          downvotes: upvote.downvotes + 1,
          karma: upvote.upvotes - upvote.downvotes - 1,
        )
      let updated_upvotes = dict.insert(state.upvotes, post_id, updated_upvote)
      let updated_state = UpvoteActorState(upvotes: updated_upvotes)
      let _ = process.send(reply, Ok(updated_upvote))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// UPVOTE RETRIEVAL
// =============================================================================

fn handle_get_upvote(
  state: UpvoteActorState,
  reply: process.Subject(Result(UpvoteData, String)),
  post_id: String,
) -> actor.Next(UpvoteActorState, UpvoteActorMessage) {
  case dict.get(state.upvotes, post_id) {
    Error(_) -> {
      let _ =
        process.send(reply, Error("Post with ID '" <> post_id <> "' not found"))
      actor.continue(state)
    }
    Ok(upvote) -> {
      let _ = process.send(reply, Ok(upvote))
      actor.continue(state)
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
