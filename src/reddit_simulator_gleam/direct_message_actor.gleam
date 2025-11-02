import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/result
import reddit_simulator_gleam/engine_types.{
  type DirectMessageActorMessage, type DirectMessageActorState,
  DirectMessageActorState, DirectMessageAddUser, DirectMessageGetMessages,
  DirectMessageSendMessage, DirectMessageShutdown,
}
import reddit_simulator_gleam/simulation_types.{
  type DirectMessage, DirectMessage,
}

// =============================================================================
// DIRECT MESSAGE ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_direct_message_actor() -> Result(
  process.Subject(DirectMessageActorMessage),
  String,
) {
  let initial_state =
    DirectMessageActorState(user_messages: dict.new(), next_message_id: 1)

  case
    actor.new(initial_state)
    |> actor.on_message(handle_direct_message_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start DirectMessageActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_direct_message_message(
  state: DirectMessageActorState,
  message: DirectMessageActorMessage,
) -> actor.Next(DirectMessageActorState, DirectMessageActorMessage) {
  case message {
    DirectMessageAddUser(reply, user_id) -> {
      handle_add_user(state, reply, user_id)
    }
    DirectMessageSendMessage(reply, sender_id, recipient_id, content) -> {
      handle_send_message(state, reply, sender_id, recipient_id, content)
    }
    DirectMessageGetMessages(reply, user_id) -> {
      handle_get_messages(state, reply, user_id)
    }
    DirectMessageShutdown -> {
      actor.stop()
    }
  }
}

// =============================================================================
// USER MANAGEMENT
// =============================================================================

fn handle_add_user(
  state: DirectMessageActorState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
) -> actor.Next(DirectMessageActorState, DirectMessageActorMessage) {
  // Check if user already exists
  case dict.get(state.user_messages, user_id) {
    Ok(_) -> {
      // User already exists, just acknowledge
      let _ = process.send(reply, Ok(Nil))
      actor.continue(state)
    }
    Error(_) -> {
      // Add user with empty message list
      let updated_user_messages = dict.insert(state.user_messages, user_id, [])
      let updated_state =
        DirectMessageActorState(
          user_messages: updated_user_messages,
          next_message_id: state.next_message_id,
        )

      let _ = process.send(reply, Ok(Nil))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// MESSAGE SENDING
// =============================================================================

fn handle_send_message(
  state: DirectMessageActorState,
  reply: process.Subject(Result(DirectMessage, String)),
  sender_id: String,
  recipient_id: String,
  content: String,
) -> actor.Next(DirectMessageActorState, DirectMessageActorMessage) {
  // Check if both users exist
  case dict.get(state.user_messages, sender_id) {
    Error(_) -> {
      let _ = process.send(reply, Error("Sender user not found"))
      actor.continue(state)
    }
    Ok(_) -> {
      case dict.get(state.user_messages, recipient_id) {
        Error(_) -> {
          let _ = process.send(reply, Error("Recipient user not found"))
          actor.continue(state)
        }
        Ok(_) -> {
          // Create new message
          let message_id = "dm_" <> int.to_string(state.next_message_id)
          let current_time = state.next_message_id

          let new_message =
            DirectMessage(
              id: message_id,
              sender_id: sender_id,
              recipient_id: recipient_id,
              content: content,
              created_at: current_time,
            )

          // Add message to both sender's and recipient's message lists
          let updated_state =
            add_message_to_users(state, new_message, sender_id, recipient_id)

          let _ = process.send(reply, Ok(new_message))
          actor.continue(updated_state)
        }
      }
    }
  }
}

// =============================================================================
// MESSAGE RETRIEVAL
// =============================================================================

fn handle_get_messages(
  state: DirectMessageActorState,
  reply: process.Subject(Result(List(DirectMessage), String)),
  user_id: String,
) -> actor.Next(DirectMessageActorState, DirectMessageActorMessage) {
  case dict.get(state.user_messages, user_id) {
    Error(_) -> {
      let _ = process.send(reply, Error("User not found"))
      actor.continue(state)
    }
    Ok(messages) -> {
      let _ = process.send(reply, Ok(messages))
      actor.continue(state)
    }
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn add_message_to_users(
  state: DirectMessageActorState,
  message: DirectMessage,
  sender_id: String,
  recipient_id: String,
) -> DirectMessageActorState {
  // Add to sender's messages
  let sender_messages =
    dict.get(state.user_messages, sender_id) |> result.unwrap([])
  let updated_sender_messages = list.append(sender_messages, [message])
  let updated_user_messages =
    dict.insert(state.user_messages, sender_id, updated_sender_messages)

  // Add to recipient's messages
  let recipient_messages =
    dict.get(updated_user_messages, recipient_id) |> result.unwrap([])
  let updated_recipient_messages = list.append(recipient_messages, [message])
  let final_user_messages =
    dict.insert(updated_user_messages, recipient_id, updated_recipient_messages)

  DirectMessageActorState(
    user_messages: final_user_messages,
    next_message_id: state.next_message_id + 1,
  )
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
