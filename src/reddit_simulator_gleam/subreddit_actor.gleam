import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import reddit_simulator_gleam/engine_types.{
  type CommentActorMessage, type PostActorMessage, type SubredditActorMessage,
  type SubredditActorState, CommentAddSubreddit, PostAddSubreddit,
  SubredditActorState, SubredditCreateSubreddit, SubredditGetSubreddit,
  SubredditGetSubredditWithMembers, SubredditJoinSubreddit,
  SubredditLeaveSubreddit, SubredditShutdown,
}
import reddit_simulator_gleam/simulation_types.{
  type Subreddit, type SubredditWithMembers, Subreddit, SubredditWithMembers,
}

// =============================================================================
// SUBREDDIT ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_subreddit_actor(
  post_actor: Option(process.Subject(PostActorMessage)),
  comment_actor: Option(process.Subject(CommentActorMessage)),
) -> Result(process.Subject(SubredditActorMessage), String) {
  let initial_state =
    SubredditActorState(
      subreddits: dict.new(),
      subreddit_members: dict.new(),
      next_subreddit_id: 1,
      post_actor: post_actor,
      comment_actor: comment_actor,
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_subreddit_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start SubredditActor: " <> error_to_string(err))
  }
}

// =============================================================================
// MESSAGE HANDLING
// =============================================================================

fn handle_subreddit_message(
  state: SubredditActorState,
  message: SubredditActorMessage,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  case message {
    SubredditCreateSubreddit(reply, name, description, creator_id) -> {
      handle_create_subreddit(state, reply, name, description, creator_id)
    }
    SubredditJoinSubreddit(reply, user_id, subreddit_id) -> {
      handle_join_subreddit(state, reply, user_id, subreddit_id)
    }
    SubredditLeaveSubreddit(reply, user_id, subreddit_id) -> {
      handle_leave_subreddit(state, reply, user_id, subreddit_id)
    }
    SubredditGetSubreddit(reply, subreddit_id) -> {
      handle_get_subreddit(state, reply, subreddit_id)
    }
    SubredditGetSubredditWithMembers(reply, subreddit_id) -> {
      handle_get_subreddit_with_members(state, reply, subreddit_id)
    }
    SubredditShutdown -> {
      actor.stop()
    }
  }
}

// =============================================================================
// SUBREDDIT CREATION
// =============================================================================

fn handle_create_subreddit(
  state: SubredditActorState,
  reply: process.Subject(Result(Subreddit, String)),
  name: String,
  description: String,
  creator_id: String,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  // Check if subreddit name already exists
  case find_subreddit_by_name(state, name) {
    Some(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with name '" <> name <> "' already exists"),
        )
      actor.continue(state)
    }
    None -> {
      // Create new subreddit; use the provided name as the ID
      let subreddit_id = name
      let current_time = 0
      // TODO: Use actual timestamp

      let new_subreddit =
        Subreddit(
          id: subreddit_id,
          name: name,
          description: description,
          created_at: current_time,
          subscriber_count: 1,
          // Creator is automatically subscribed
          moderator_ids: [creator_id],
        )

      // Add subreddit to state
      let updated_subreddits =
        dict.insert(state.subreddits, subreddit_id, new_subreddit)
      let updated_members =
        dict.insert(state.subreddit_members, subreddit_id, [creator_id])

      let updated_state =
        SubredditActorState(
          subreddits: updated_subreddits,
          subreddit_members: updated_members,
          next_subreddit_id: state.next_subreddit_id + 1,
          post_actor: state.post_actor,
          comment_actor: state.comment_actor,
        )

      // Notify Post actor about new subreddit
      case state.post_actor {
        Some(post_actor_subject) -> {
          // Create a dummy reply subject for the notification
          let dummy_reply = process.new_subject()
          let post_message = PostAddSubreddit(dummy_reply, subreddit_id)
          let _ = process.send(post_actor_subject, post_message)
          // Consume reply to avoid unexpected message warnings
          let _ = process.receive(dummy_reply, 100)
          #()
        }
        None -> {
          #()
        }
      }

      // Notify Comment actor about new subreddit
      case state.comment_actor {
        Some(comment_actor_subject) -> {
          // Create a dummy reply subject for the notification
          let dummy_reply = process.new_subject()
          let comment_message = CommentAddSubreddit(dummy_reply, subreddit_id)
          let _ = process.send(comment_actor_subject, comment_message)
          // Consume reply to avoid unexpected message warnings
          let _ = process.receive(dummy_reply, 100)
          #()
        }
        None -> {
          #()
        }
      }

      let _ = process.send(reply, Ok(new_subreddit))
      actor.continue(updated_state)
    }
  }
}

// =============================================================================
// SUBREDDIT JOINING
// =============================================================================

fn handle_join_subreddit(
  state: SubredditActorState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  subreddit_id: String,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(subreddit) -> {
      case dict.get(state.subreddit_members, subreddit_id) {
        Error(_) -> {
          // This shouldn't happen if data is consistent
          let _ =
            process.send(
              reply,
              Error("Internal error: subreddit members not found"),
            )
          actor.continue(state)
        }
        Ok(current_members) -> {
          // Check if user is already a member
          case is_user_member(current_members, user_id) {
            True -> {
              let _ = process.send(reply, Ok(Nil))
              actor.continue(state)
            }
            False -> {
              // Add user to members list
              let updated_members = list.append(current_members, [user_id])
              let updated_members_dict =
                dict.insert(
                  state.subreddit_members,
                  subreddit_id,
                  updated_members,
                )

              // Update subscriber count
              let updated_subreddit =
                Subreddit(
                  id: subreddit.id,
                  name: subreddit.name,
                  description: subreddit.description,
                  created_at: subreddit.created_at,
                  subscriber_count: subreddit.subscriber_count + 1,
                  moderator_ids: subreddit.moderator_ids,
                )
              let updated_subreddits =
                dict.insert(state.subreddits, subreddit_id, updated_subreddit)

              let updated_state =
                SubredditActorState(
                  subreddits: updated_subreddits,
                  subreddit_members: updated_members_dict,
                  next_subreddit_id: state.next_subreddit_id,
                  post_actor: state.post_actor,
                  comment_actor: state.comment_actor,
                )

              let _ = process.send(reply, Ok(Nil))
              actor.continue(updated_state)
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// SUBREDDIT LEAVING
// =============================================================================

fn handle_leave_subreddit(
  state: SubredditActorState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  subreddit_id: String,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(subreddit) -> {
      case dict.get(state.subreddit_members, subreddit_id) {
        Error(_) -> {
          let _ =
            process.send(
              reply,
              Error("Internal error: subreddit members not found"),
            )
          actor.continue(state)
        }
        Ok(current_members) -> {
          // Check if user is a member
          case is_user_member(current_members, user_id) {
            False -> {
              let _ = process.send(reply, Ok(Nil))
              actor.continue(state)
            }
            True -> {
              // Remove user from members list
              let updated_members =
                remove_user_from_list(current_members, user_id)
              let updated_members_dict =
                dict.insert(
                  state.subreddit_members,
                  subreddit_id,
                  updated_members,
                )

              // Update subscriber count
              let updated_subreddit =
                Subreddit(
                  id: subreddit.id,
                  name: subreddit.name,
                  description: subreddit.description,
                  created_at: subreddit.created_at,
                  subscriber_count: subreddit.subscriber_count - 1,
                  moderator_ids: subreddit.moderator_ids,
                )
              let updated_subreddits =
                dict.insert(state.subreddits, subreddit_id, updated_subreddit)

              let updated_state =
                SubredditActorState(
                  subreddits: updated_subreddits,
                  subreddit_members: updated_members_dict,
                  next_subreddit_id: state.next_subreddit_id,
                  post_actor: state.post_actor,
                  comment_actor: state.comment_actor,
                )

              let _ = process.send(reply, Ok(Nil))
              actor.continue(updated_state)
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// SUBREDDIT RETRIEVAL
// =============================================================================

fn handle_get_subreddit(
  state: SubredditActorState,
  reply: process.Subject(Result(Subreddit, String)),
  subreddit_id: String,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(subreddit) -> {
      // Get member information for logging
      case dict.get(state.subreddit_members, subreddit_id) {
        Error(_) -> {
          #()
        }
        Ok(_member_ids) -> {
          #()
        }
      }
      let _ = process.send(reply, Ok(subreddit))
      actor.continue(state)
    }
  }
}

fn handle_get_subreddit_with_members(
  state: SubredditActorState,
  reply: process.Subject(Result(SubredditWithMembers, String)),
  subreddit_id: String,
) -> actor.Next(SubredditActorState, SubredditActorMessage) {
  case dict.get(state.subreddits, subreddit_id) {
    Error(_) -> {
      let _ =
        process.send(
          reply,
          Error("Subreddit with ID '" <> subreddit_id <> "' not found"),
        )
      actor.continue(state)
    }
    Ok(subreddit) -> {
      // Get member information
      case dict.get(state.subreddit_members, subreddit_id) {
        Error(_) -> {
          let subreddit_with_members =
            SubredditWithMembers(subreddit: subreddit, member_ids: [])
          let _ = process.send(reply, Ok(subreddit_with_members))
          actor.continue(state)
        }
        Ok(member_ids) -> {
          let subreddit_with_members =
            SubredditWithMembers(subreddit: subreddit, member_ids: member_ids)
          let _ = process.send(reply, Ok(subreddit_with_members))
          actor.continue(state)
        }
      }
    }
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn find_subreddit_by_name(
  state: SubredditActorState,
  name: String,
) -> Option(Subreddit) {
  dict.fold(state.subreddits, None, fn(acc, _id, subreddit) {
    case acc {
      Some(_) -> acc
      None -> {
        case subreddit.name == name {
          True -> Some(subreddit)
          False -> None
        }
      }
    }
  })
}

fn is_user_member(members: List(String), user_id: String) -> Bool {
  list.any(members, fn(id) { id == user_id })
}

fn remove_user_from_list(members: List(String), user_id: String) -> List(String) {
  list.filter(members, fn(id) { id != user_id })
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
