import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import reddit_simulator_gleam/all_types.{
  type Comment, type DirectMessage, type FeedItem, type MasterEngineMessage,
  type MasterEngineState, type Post, type RequestType, type StatusCode,
  type Subreddit, type SubredditActorMessage, type SubredditWithMembers,
  type SystemStats, type User, type UserActorMessage, type Vote, type VoteTarget,
  type VoteType, Comment, CommentTarget, CreateComment, CreatePost,
  CreateSubreddit, DirectMessage, Downvote, FeedItem, GetComment,
  GetDirectMessages, GetPost, GetPostComments, GetSubreddit, GetSubredditPosts,
  GetSubredditWithMembers, GetSystemStats, GetUser, GetUserFeed,
  MarkMessageAsRead, MasterEngineState, Post, PostTarget, ProcessRequest,
  RegisterUser, ReqCreateComment, ReqCreatePost, ReqCreateSubreddit,
  ReqCreateUser, ReqGetComment, ReqGetDirectMessages, ReqGetPost,
  ReqGetPostComments, ReqGetSubreddit, ReqGetSubredditPosts, ReqGetSystemStats,
  ReqGetUser, ReqGetUserFeed, ReqMarkMessageAsRead, ReqSendDirectMessage,
  ReqSubscribeToSubreddit, ReqUnknown, ReqUnsubscribeFromSubreddit,
  ReqVoteOnComment, ReqVoteOnPost, SendDirectMessage, Shutdown, Status200,
  Status404, Subreddit, SubredditCreateSubreddit, SubredditGetSubreddit,
  SubredditGetSubredditWithMembers, SubredditJoinSubreddit,
  SubredditLeaveSubreddit, SubredditWithMembers, SubscribeToSubreddit,
  SystemStats, UnsubscribeFromSubreddit, Upvote, User, UserGetUser,
  UserRegisterUser, Vote, VoteOnComment, VoteOnPost, parse_request_type,
  status_code_to_string,
}
import reddit_simulator_gleam/subreddit_actor.{create_subreddit_actor}
import reddit_simulator_gleam/user_actor.{create_user_actor}

// =============================================================================
// MASTER ENGINE ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_master_engine_actor() -> Result(
  process.Subject(MasterEngineMessage),
  String,
) {
  // First create all worker actors
  case create_all_worker_actors() {
    Ok(worker_actors) -> {
      // Create the master engine actor with all worker actors
      let master_state =
        MasterEngineState(
          user_actor: worker_actors.user_actor,
          subreddit_actor: worker_actors.subreddit_actor,
        )

      case
        actor.new(master_state)
        |> actor.on_message(handle_master_engine_message)
        |> actor.start()
      {
        Ok(actor_data) -> Ok(actor_data.data)
        Error(err) ->
          Error("Failed to start MasterEngineActor: " <> error_to_string(err))
      }
    }
    Error(msg) -> Error("Failed to create worker actors: " <> msg)
  }
}

// =============================================================================
// WORKER ACTOR CREATION
// =============================================================================

type WorkerActors {
  WorkerActors(
    user_actor: process.Subject(UserActorMessage),
    subreddit_actor: process.Subject(SubredditActorMessage),
  )
}

fn create_all_worker_actors() -> Result(WorkerActors, String) {
  // Create UserActor
  case create_user_actor() {
    Ok(user_actor_subject) -> {
      // Create SubredditActor
      case create_subreddit_actor() {
        Ok(subreddit_actor_subject) -> {
          let worker_actors =
            WorkerActors(
              user_actor: user_actor_subject,
              subreddit_actor: subreddit_actor_subject,
            )
          Ok(worker_actors)
        }
        Error(msg) -> Error("Failed to create SubredditActor: " <> msg)
      }
    }
    Error(msg) -> Error("Failed to create UserActor: " <> msg)
  }
}

fn handle_master_engine_message(
  state: MasterEngineState,
  message: MasterEngineMessage,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  case message {
    // String-based request routing
    ProcessRequest(reply, request_type, request_data) -> {
      handle_process_request(state, reply, request_type, request_data)
    }

    // User management
    RegisterUser(reply, username, email) -> {
      handle_register_user(state, reply, username, email)
    }
    GetUser(reply, user_id) -> {
      handle_get_user(state, reply, user_id)
    }

    // Subreddit management
    CreateSubreddit(reply, name, description, creator_id) -> {
      handle_create_subreddit(state, reply, name, description, creator_id)
    }
    GetSubreddit(reply, subreddit_id) -> {
      handle_get_subreddit(state, reply, subreddit_id)
    }
    GetSubredditWithMembers(reply, subreddit_id) -> {
      handle_get_subreddit_with_members(state, reply, subreddit_id)
    }
    SubscribeToSubreddit(reply, user_id, subreddit_id) -> {
      handle_subscribe_to_subreddit(state, reply, user_id, subreddit_id)
    }
    UnsubscribeFromSubreddit(reply, user_id, subreddit_id) -> {
      handle_unsubscribe_from_subreddit(state, reply, user_id, subreddit_id)
    }

    // Post management
    CreatePost(reply, title, content, author_id, subreddit_id) -> {
      handle_create_post(state, reply, title, content, author_id, subreddit_id)
    }
    GetPost(reply, post_id) -> {
      handle_get_post(state, reply, post_id)
    }
    GetSubredditPosts(reply, subreddit_id, limit) -> {
      handle_get_subreddit_posts(state, reply, subreddit_id, limit)
    }

    // Comment management
    CreateComment(reply, content, author_id, post_id, parent_comment_id) -> {
      handle_create_comment(
        state,
        reply,
        content,
        author_id,
        post_id,
        parent_comment_id,
      )
    }
    GetComment(reply, comment_id) -> {
      handle_get_comment(state, reply, comment_id)
    }
    GetPostComments(reply, post_id) -> {
      handle_get_post_comments(state, reply, post_id)
    }

    // Voting
    VoteOnPost(reply, user_id, post_id, vote_type) -> {
      handle_vote_on_post(state, reply, user_id, post_id, vote_type)
    }
    VoteOnComment(reply, user_id, comment_id, vote_type) -> {
      handle_vote_on_comment(state, reply, user_id, comment_id, vote_type)
    }

    // Feed
    GetUserFeed(reply, user_id, limit) -> {
      handle_get_user_feed(state, reply, user_id, limit)
    }

    // Direct messages
    SendDirectMessage(reply, sender_id, recipient_id, content) -> {
      handle_send_direct_message(state, reply, sender_id, recipient_id, content)
    }
    GetDirectMessages(reply, user_id) -> {
      handle_get_direct_messages(state, reply, user_id)
    }
    MarkMessageAsRead(reply, user_id, message_id) -> {
      handle_mark_message_as_read(state, reply, user_id, message_id)
    }

    // System management
    GetSystemStats(reply) -> {
      handle_get_system_stats(state, reply)
    }
    Shutdown -> {
      io.println("MasterEngineActor shutting down...")
      actor.stop()
    }
  }
}

// =============================================================================
// USER MANAGEMENT HANDLERS
// =============================================================================

fn handle_register_user(
  state: MasterEngineState,
  reply: process.Subject(String),
  username: String,
  email: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let user_message = UserRegisterUser(reply, username, email)
  io.println(
    "🔄 MASTER ENGINE forwarding registration to UserActor for: " <> username,
  )
  let _ = process.send(state.user_actor, user_message)
  io.println("User registration request sent to UserActor")
  actor.continue(state)
}

fn handle_get_user(
  state: MasterEngineState,
  reply: process.Subject(String),
  user_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let user_message = UserGetUser(reply, user_id)
  io.println(
    "🔄 MASTER ENGINE forwarding get user to UserActor for: " <> user_id,
  )
  let _ = process.send(state.user_actor, user_message)
  io.println("User retrieval request sent to UserActor")
  actor.continue(state)
}

// =============================================================================
// SUBREDDIT MANAGEMENT HANDLERS
// =============================================================================

fn handle_create_subreddit(
  state: MasterEngineState,
  reply: process.Subject(Result(Subreddit, String)),
  name: String,
  description: String,
  creator_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let subreddit_message =
    SubredditCreateSubreddit(reply, name, description, creator_id)
  io.println(
    "🔄 MASTER ENGINE forwarding subreddit creation to SubredditActor for: "
    <> name,
  )
  let _ = process.send(state.subreddit_actor, subreddit_message)
  io.println("Subreddit creation request sent to SubredditActor")
  actor.continue(state)
}

fn handle_get_subreddit(
  state: MasterEngineState,
  reply: process.Subject(Result(Subreddit, String)),
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let subreddit_message = SubredditGetSubreddit(reply, subreddit_id)
  io.println(
    "🔄 MASTER ENGINE forwarding subreddit retrieval to SubredditActor for: "
    <> subreddit_id,
  )
  let _ = process.send(state.subreddit_actor, subreddit_message)
  io.println("Subreddit retrieval request sent to SubredditActor")
  actor.continue(state)
}

fn handle_subscribe_to_subreddit(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let subreddit_message = SubredditJoinSubreddit(reply, user_id, subreddit_id)
  io.println(
    "🔄 MASTER ENGINE forwarding subscription to SubredditActor for user: "
    <> user_id
    <> " to subreddit: "
    <> subreddit_id,
  )
  let _ = process.send(state.subreddit_actor, subreddit_message)
  io.println("Subscription request sent to SubredditActor")
  actor.continue(state)
}

fn handle_unsubscribe_from_subreddit(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let subreddit_message = SubredditLeaveSubreddit(reply, user_id, subreddit_id)
  io.println(
    "🔄 MASTER ENGINE forwarding unsubscription to SubredditActor for user: "
    <> user_id
    <> " from subreddit: "
    <> subreddit_id,
  )
  let _ = process.send(state.subreddit_actor, subreddit_message)
  io.println("Unsubscription request sent to SubredditActor")
  actor.continue(state)
}

fn handle_get_subreddit_with_members(
  state: MasterEngineState,
  reply: process.Subject(Result(SubredditWithMembers, String)),
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let subreddit_message = SubredditGetSubredditWithMembers(reply, subreddit_id)
  io.println(
    "🔄 MASTER ENGINE forwarding subreddit retrieval with members to SubredditActor for: "
    <> subreddit_id,
  )
  let _ = process.send(state.subreddit_actor, subreddit_message)
  io.println("Subreddit retrieval with members request sent to SubredditActor")
  actor.continue(state)
}

// =============================================================================
// POST MANAGEMENT HANDLERS
// =============================================================================

fn handle_create_post(
  state: MasterEngineState,
  reply: process.Subject(Result(Post, String)),
  title: String,
  content: String,
  author_id: String,
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement post creation
  let _ = process.send(reply, Error("Post creation not implemented"))
  actor.continue(state)
}

fn handle_get_post(
  state: MasterEngineState,
  reply: process.Subject(Result(Post, String)),
  post_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement post retrieval
  let _ = process.send(reply, Error("Post retrieval not implemented"))
  actor.continue(state)
}

fn handle_get_subreddit_posts(
  state: MasterEngineState,
  reply: process.Subject(Result(List(Post), String)),
  subreddit_id: String,
  limit: Int,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement subreddit posts retrieval
  let _ = process.send(reply, Ok([]))
  actor.continue(state)
}

// =============================================================================
// COMMENT MANAGEMENT HANDLERS
// =============================================================================

fn handle_create_comment(
  state: MasterEngineState,
  reply: process.Subject(Result(Comment, String)),
  content: String,
  author_id: String,
  post_id: String,
  parent_comment_id: Option(String),
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement comment creation
  let _ = process.send(reply, Error("Comment creation not implemented"))
  actor.continue(state)
}

fn handle_get_comment(
  state: MasterEngineState,
  reply: process.Subject(Result(Comment, String)),
  comment_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement comment retrieval
  let _ = process.send(reply, Error("Comment retrieval not implemented"))
  actor.continue(state)
}

fn handle_get_post_comments(
  state: MasterEngineState,
  reply: process.Subject(Result(List(Comment), String)),
  post_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement post comments retrieval
  let _ = process.send(reply, Ok([]))
  actor.continue(state)
}

// =============================================================================
// VOTING HANDLERS
// =============================================================================

fn handle_vote_on_post(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  post_id: String,
  vote_type: VoteType,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement post voting logic
  let _ = process.send(reply, Ok(Nil))
  actor.continue(state)
}

fn handle_vote_on_comment(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  comment_id: String,
  vote_type: VoteType,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement comment voting logic
  let _ = process.send(reply, Ok(Nil))
  actor.continue(state)
}

// =============================================================================
// FEED HANDLERS
// =============================================================================

fn handle_get_user_feed(
  state: MasterEngineState,
  reply: process.Subject(Result(List(FeedItem), String)),
  user_id: String,
  limit: Int,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement user feed generation
  let _ = process.send(reply, Ok([]))
  actor.continue(state)
}

// =============================================================================
// DIRECT MESSAGE HANDLERS
// =============================================================================

fn handle_send_direct_message(
  state: MasterEngineState,
  reply: process.Subject(Result(DirectMessage, String)),
  sender_id: String,
  recipient_id: String,
  content: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement direct message sending
  let _ = process.send(reply, Error("Direct message sending not implemented"))
  actor.continue(state)
}

fn handle_get_direct_messages(
  state: MasterEngineState,
  reply: process.Subject(Result(List(DirectMessage), String)),
  user_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement direct messages retrieval
  let _ = process.send(reply, Ok([]))
  actor.continue(state)
}

fn handle_mark_message_as_read(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  user_id: String,
  message_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement mark as read logic
  let _ = process.send(reply, Ok(Nil))
  actor.continue(state)
}

// =============================================================================
// SYSTEM MANAGEMENT HANDLERS
// =============================================================================

fn handle_get_system_stats(
  state: MasterEngineState,
  reply: process.Subject(Result(SystemStats, String)),
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement system stats
  let _ = process.send(reply, Error("System stats not implemented"))
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

// =============================================================================
// STRING-BASED REQUEST ROUTING
// =============================================================================

fn handle_process_request(
  state: MasterEngineState,
  reply: process.Subject(Result(String, String)),
  request_type: String,
  request_data: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let parsed_type = parse_request_type(request_type)

  case parsed_type {
    ReqCreateUser -> {
      // Route to UserActor
      let _ = process.send(reply, Ok("User creation routed to UserActor"))
      actor.continue(state)
    }
    ReqGetUser -> {
      // Route to UserActor
      let _ = process.send(reply, Ok("User retrieval routed to UserActor"))
      actor.continue(state)
    }
    ReqCreateSubreddit -> {
      let _ =
        process.send(reply, Ok("Subreddit creation routed to legacy handler"))
      actor.continue(state)
    }
    ReqCreatePost -> {
      let _ = process.send(reply, Ok("Post creation routed to legacy handler"))
      actor.continue(state)
    }
    ReqCreateComment -> {
      let _ =
        process.send(reply, Ok("Comment creation routed to legacy handler"))
      actor.continue(state)
    }
    ReqVoteOnPost -> {
      let _ = process.send(reply, Ok("Post voting routed to legacy handler"))
      actor.continue(state)
    }
    ReqVoteOnComment -> {
      let _ = process.send(reply, Ok("Comment voting routed to legacy handler"))
      actor.continue(state)
    }
    ReqGetUserFeed -> {
      let _ = process.send(reply, Ok("Feed retrieval routed to legacy handler"))
      actor.continue(state)
    }
    ReqSendDirectMessage -> {
      let _ =
        process.send(
          reply,
          Ok("Direct message sending routed to legacy handler"),
        )
      actor.continue(state)
    }
    ReqGetDirectMessages -> {
      let _ =
        process.send(
          reply,
          Ok("Direct message retrieval routed to legacy handler"),
        )
      actor.continue(state)
    }
    ReqGetSystemStats -> {
      let _ =
        process.send(
          reply,
          Ok("System stats retrieval routed to legacy handler"),
        )
      actor.continue(state)
    }
    ReqUnknown -> {
      let _ =
        process.send(reply, Error("Unknown request type: " <> request_type))
      actor.continue(state)
    }
    _ -> {
      let _ =
        process.send(
          reply,
          Ok(
            "Request type '" <> request_type <> "' with data: " <> request_data,
          ),
        )
      actor.continue(state)
    }
  }
}
