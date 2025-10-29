import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{
  type DirectMessageActorMessage, type UserActorMessage,
  type UserEngineActorState, DirectMessageAddUser, UserEngineActorState,
  UserGetUser, UserRegisterUser, UserShutdown,
}
import reddit_simulator_gleam/simulation_types.{
  Status200, Status404, User, status_code_to_string,
}

// =============================================================================
// USER ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_user_actor(
  direct_message_actor: process.Subject(DirectMessageActorMessage),
) -> Result(process.Subject(UserActorMessage), String) {
  let initial_state =
    UserEngineActorState(
      users: dict.new(),
      next_user_id: 1,
      direct_message_actor: option.Some(direct_message_actor),
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_user_actor_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) -> Error("Failed to start UserActor: " <> error_to_string(err))
  }
}

fn handle_user_actor_message(
  state: UserEngineActorState,
  message: UserActorMessage,
) -> actor.Next(UserEngineActorState, UserActorMessage) {
  case message {
    UserRegisterUser(reply, username, email) -> {
      handle_register_user(state, reply, username, email)
    }
    UserGetUser(reply, user_id) -> {
      handle_get_user(state, reply, user_id)
    }
    UserShutdown -> {
      io.println("UserActor shutting down...")
      actor.stop()
    }
  }
}

// =============================================================================
// USER MANAGEMENT HANDLERS
// =============================================================================

fn handle_register_user(
  state: UserEngineActorState,
  reply: process.Subject(String),
  _username: String,
  _email: String,
) -> actor.Next(UserEngineActorState, UserActorMessage) {
  let user_id = "user_" <> int.to_string(state.next_user_id)
  let user = User(id: user_id)

  let updated_state =
    UserEngineActorState(
      users: dict.insert(state.users, user_id, user),
      next_user_id: state.next_user_id + 1,
      direct_message_actor: state.direct_message_actor,
    )

  // Send message to DirectMessageActor to add user
  case state.direct_message_actor {
    option.Some(dm_actor) -> {
      let dm_reply = process.new_subject()
      let _ = process.send(dm_actor, DirectMessageAddUser(dm_reply, user_id))
    }
    option.None -> {
      // DirectMessageActor not available, continue without error
      io.println("⚠️ DirectMessageActor not available for user " <> user_id)
    }
  }

  let status_code = Status200
  let response = status_code_to_string(status_code) <> ":" <> user_id
  io.println("📤 USER ACTOR SENDING: " <> response)
  let _ = process.send(reply, response)
  actor.continue(updated_state)
}

fn handle_get_user(
  state: UserEngineActorState,
  reply: process.Subject(String),
  user_id: String,
) -> actor.Next(UserEngineActorState, UserActorMessage) {
  case dict.get(state.users, user_id) {
    Ok(user) -> {
      let status_code = Status200
      let response = status_code_to_string(status_code) <> ":" <> user.id
      io.println("📤 USER ACTOR SENDING: " <> response)
      let _ = process.send(reply, response)
      actor.continue(state)
    }
    Error(_) -> {
      let status_code = Status404
      let response = status_code_to_string(status_code) <> ":User not found"
      io.println("📤 USER ACTOR SENDING: " <> response)
      let _ = process.send(reply, response)
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
