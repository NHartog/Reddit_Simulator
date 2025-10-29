import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/option.{type Option, Some}
import gleam/otp/actor
import reddit_simulator_gleam/comment_actor.{create_comment_actor}
import reddit_simulator_gleam/direct_message_actor.{create_direct_message_actor}
import reddit_simulator_gleam/engine_types.{
  type CommentActorMessage, type DirectMessageActorMessage,
  type FeedActorMessage, type MasterEngineMessage, type MasterEngineState,
  type PostActorMessage, type SubredditActorMessage, type SystemStats,
  type UpvoteActorMessage, type UserActorMessage, CommentCreateComment,
  CommentGetComment, CommentGetSubredditComments, CreateComment, CreatePost,
  CreateSubreddit, DirectMessageGetMessages, DirectMessageSendMessage,
  FeedGetFeed, GetComment, GetDirectMessages, GetFeed, GetPost, GetSubreddit,
  GetSubredditComments, GetSubredditPosts, GetSubredditWithMembers,
  GetSystemStats, GetUser, GetUserFeed, MasterEngineState, PostCreatePost,
  PostGetPost, PostGetSubredditPosts, RegisterUser, SendDirectMessage, Shutdown,
  SubredditCreateSubreddit, SubredditGetSubreddit,
  SubredditGetSubredditWithMembers, SubredditJoinSubreddit,
  SubredditLeaveSubreddit, SubscribeToSubreddit, UnsubscribeFromSubreddit,
  UpvoteDownvote, UpvoteGetUpvote, UpvoteUpvote, UserGetUser, UserRegisterUser,
  VoteOnComment, VoteOnPost,
}
import reddit_simulator_gleam/feed_actor.{create_feed_actor}
import reddit_simulator_gleam/post_actor.{create_post_actor}
import reddit_simulator_gleam/simulation_types.{
  type Comment, type CommentTree, type DirectMessage, type FeedItem,
  type FeedObject, type Post, type Subreddit, type SubredditWithMembers,
  type VoteType, Downvote, Post, Upvote,
}
import reddit_simulator_gleam/subreddit_actor.{create_subreddit_actor}
import reddit_simulator_gleam/upvote_actor.{create_upvote_actor}
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
          post_actor: worker_actors.post_actor,
          comment_actor: worker_actors.comment_actor,
          upvote_actor: worker_actors.upvote_actor,
          feed_actor: worker_actors.feed_actor,
          direct_message_actor: worker_actors.direct_message_actor,
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
    post_actor: process.Subject(PostActorMessage),
    comment_actor: process.Subject(CommentActorMessage),
    upvote_actor: process.Subject(UpvoteActorMessage),
    feed_actor: process.Subject(FeedActorMessage),
    direct_message_actor: process.Subject(DirectMessageActorMessage),
  )
}

fn create_all_worker_actors() -> Result(WorkerActors, String) {
  // Create DirectMessageActor first
  case create_direct_message_actor() {
    Ok(direct_message_actor_subject) -> {
      // Create UserActor with DirectMessageActor reference
      case create_user_actor(direct_message_actor_subject) {
        Ok(user_actor_subject) -> {
          // Create UpvoteActor first
          case create_upvote_actor() {
            Ok(upvote_actor_subject) -> {
              // Create FeedActor
              case create_feed_actor() {
                Ok(feed_actor_subject) -> {
                  // Create PostActor with UpvoteActor and FeedActor
                  case
                    create_post_actor(upvote_actor_subject, feed_actor_subject)
                  {
                    Ok(post_actor_subject) -> {
                      // Create CommentActor
                      case create_comment_actor() {
                        Ok(comment_actor_subject) -> {
                          // Create SubredditActor with PostActor and CommentActor references
                          case
                            create_subreddit_actor(
                              Some(post_actor_subject),
                              Some(comment_actor_subject),
                            )
                          {
                            Ok(subreddit_actor_subject) -> {
                              let worker_actors =
                                WorkerActors(
                                  user_actor: user_actor_subject,
                                  subreddit_actor: subreddit_actor_subject,
                                  post_actor: post_actor_subject,
                                  comment_actor: comment_actor_subject,
                                  upvote_actor: upvote_actor_subject,
                                  feed_actor: feed_actor_subject,
                                  direct_message_actor: direct_message_actor_subject,
                                )
                              Ok(worker_actors)
                            }
                            Error(msg) ->
                              Error("Failed to create SubredditActor: " <> msg)
                          }
                        }
                        Error(msg) ->
                          Error("Failed to create CommentActor: " <> msg)
                      }
                    }
                    Error(msg) -> Error("Failed to create PostActor: " <> msg)
                  }
                }
                Error(msg) -> Error("Failed to create FeedActor: " <> msg)
              }
            }
            Error(msg) -> Error("Failed to create UpvoteActor: " <> msg)
          }
        }
        Error(msg) -> Error("Failed to create UserActor: " <> msg)
      }
    }
    Error(msg) -> Error("Failed to create DirectMessageActor: " <> msg)
  }
}

fn handle_master_engine_message(
  state: MasterEngineState,
  message: MasterEngineMessage,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  case message {
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
    CreateComment(reply, content, author_id, subreddit_id, parent_comment_id) -> {
      handle_create_comment(
        state,
        reply,
        content,
        author_id,
        subreddit_id,
        parent_comment_id,
      )
    }
    GetComment(reply, comment_id) -> {
      handle_get_comment(state, reply, comment_id)
    }
    GetSubredditComments(reply, subreddit_id) -> {
      handle_get_subreddit_comments(state, reply, subreddit_id)
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
    GetFeed(reply, limit) -> {
      handle_get_feed(state, reply, limit)
    }

    // Direct messages
    SendDirectMessage(reply, sender_id, recipient_id, content) -> {
      handle_send_direct_message(state, reply, sender_id, recipient_id, content)
    }
    GetDirectMessages(reply, user_id) -> {
      handle_get_direct_messages(state, reply, user_id)
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
  let post_message =
    PostCreatePost(reply, title, content, author_id, subreddit_id)
  io.println(
    "🔄 MASTER ENGINE forwarding post creation to PostActor for: " <> title,
  )
  let _ = process.send(state.post_actor, post_message)
  io.println("Post creation request sent to PostActor")
  actor.continue(state)
}

fn handle_get_post(
  state: MasterEngineState,
  reply: process.Subject(Result(Post, String)),
  post_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // First get the post from PostActor
  let post_reply = process.new_subject()
  let post_message = PostGetPost(post_reply, post_id)
  io.println(
    "🔄 MASTER ENGINE forwarding post retrieval to PostActor for: " <> post_id,
  )
  let _ = process.send(state.post_actor, post_message)
  io.println("Post retrieval request sent to PostActor")

  case process.receive(post_reply, 1000) {
    Ok(Ok(post)) -> {
      // Now get upvote data from UpvoteActor
      let upvote_reply = process.new_subject()
      let upvote_message = UpvoteGetUpvote(upvote_reply, post_id)
      let _ = process.send(state.upvote_actor, upvote_message)

      case process.receive(upvote_reply, 1000) {
        Ok(Ok(upvote_data)) -> {
          // Merge post data with upvote data
          let updated_post =
            Post(
              id: post.id,
              title: post.title,
              content: post.content,
              author_id: post.author_id,
              subreddit_id: post.subreddit_id,
              created_at: post.created_at,
              score: post.score,
              upvotes: upvote_data.upvotes,
              downvotes: upvote_data.downvotes,
              comment_count: post.comment_count,
            )
          io.println(
            "📤 MASTER ENGINE: Retrieved post with upvote data (upvotes: "
            <> int.to_string(updated_post.upvotes)
            <> ", downvotes: "
            <> int.to_string(updated_post.downvotes)
            <> ")",
          )
          let _ = process.send(reply, Ok(updated_post))
          actor.continue(state)
        }
        _ -> {
          // If upvote data not available, return post as-is
          io.println("📤 MASTER ENGINE: Retrieved post without upvote data")
          let _ = process.send(reply, Ok(post))
          actor.continue(state)
        }
      }
    }
    Ok(Error(msg)) -> {
      let _ = process.send(reply, Error(msg))
      actor.continue(state)
    }
    Error(_) -> {
      let _ = process.send(reply, Error("Post retrieval timeout"))
      actor.continue(state)
    }
  }
}

fn handle_get_subreddit_posts(
  state: MasterEngineState,
  reply: process.Subject(Result(List(Post), String)),
  subreddit_id: String,
  limit: Int,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let post_message = PostGetSubredditPosts(reply, subreddit_id, limit)
  io.println(
    "🔄 MASTER ENGINE forwarding subreddit posts retrieval to PostActor for: "
    <> subreddit_id,
  )
  let _ = process.send(state.post_actor, post_message)
  io.println("Subreddit posts retrieval request sent to PostActor")
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
  subreddit_id: String,
  parent_comment_id: Option(String),
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let comment_message =
    CommentCreateComment(
      reply,
      content,
      author_id,
      subreddit_id,
      parent_comment_id,
    )
  let _ = process.send(state.comment_actor, comment_message)
  actor.continue(state)
}

fn handle_get_comment(
  state: MasterEngineState,
  reply: process.Subject(Result(Comment, String)),
  comment_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let comment_message = CommentGetComment(reply, comment_id)
  let _ = process.send(state.comment_actor, comment_message)
  actor.continue(state)
}

fn handle_get_subreddit_comments(
  state: MasterEngineState,
  reply: process.Subject(Result(CommentTree, String)),
  subreddit_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let comment_message = CommentGetSubredditComments(reply, subreddit_id)
  let _ = process.send(state.comment_actor, comment_message)
  actor.continue(state)
}

// =============================================================================
// VOTING HANDLERS
// =============================================================================

fn handle_vote_on_post(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  _user_id: String,
  post_id: String,
  vote_type: VoteType,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // Forward vote directly to UpvoteActor
  case vote_type {
    Upvote -> {
      let upvote_reply = process.new_subject()
      let upvote_message = UpvoteUpvote(upvote_reply, post_id)
      let _ = process.send(state.upvote_actor, upvote_message)

      case process.receive(upvote_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ Post upvoted successfully")
          let _ = process.send(reply, Ok(Nil))
          actor.continue(state)
        }
        Ok(Error(msg)) -> {
          io.println("✗ Post upvote failed: " <> msg)
          let _ = process.send(reply, Error(msg))
          actor.continue(state)
        }
        Error(_) -> {
          io.println("✗ Post upvote timeout")
          let _ = process.send(reply, Error("Upvote timeout"))
          actor.continue(state)
        }
      }
    }
    Downvote -> {
      let upvote_reply = process.new_subject()
      let upvote_message = UpvoteDownvote(upvote_reply, post_id)
      let _ = process.send(state.upvote_actor, upvote_message)

      case process.receive(upvote_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ Post downvoted successfully")
          let _ = process.send(reply, Ok(Nil))
          actor.continue(state)
        }
        Ok(Error(msg)) -> {
          io.println("✗ Post downvote failed: " <> msg)
          let _ = process.send(reply, Error(msg))
          actor.continue(state)
        }
        Error(_) -> {
          io.println("✗ Post downvote timeout")
          let _ = process.send(reply, Error("Downvote timeout"))
          actor.continue(state)
        }
      }
    }
  }
}

fn handle_vote_on_comment(
  state: MasterEngineState,
  reply: process.Subject(Result(Nil, String)),
  _user_id: String,
  _comment_id: String,
  _vote_type: VoteType,
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
  _user_id: String,
  _limit: Int,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  // TODO: Implement user feed generation
  let _ = process.send(reply, Ok([]))
  actor.continue(state)
}

fn handle_get_feed(
  state: MasterEngineState,
  reply: process.Subject(Result(List(FeedObject), String)),
  limit: Int,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let feed_message = FeedGetFeed(reply, limit)
  io.println(
    "🔄 MASTER ENGINE forwarding feed retrieval to FeedActor with limit: "
    <> int.to_string(limit),
  )
  let _ = process.send(state.feed_actor, feed_message)
  io.println("Feed retrieval request sent to FeedActor")
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
  let dm_message =
    DirectMessageSendMessage(reply, sender_id, recipient_id, content)
  io.println(
    "🔄 MASTER ENGINE forwarding direct message to DirectMessageActor from: "
    <> sender_id
    <> " to: "
    <> recipient_id,
  )
  let _ = process.send(state.direct_message_actor, dm_message)
  io.println("Direct message request sent to DirectMessageActor")
  actor.continue(state)
}

fn handle_get_direct_messages(
  state: MasterEngineState,
  reply: process.Subject(Result(List(DirectMessage), String)),
  user_id: String,
) -> actor.Next(MasterEngineState, MasterEngineMessage) {
  let dm_message = DirectMessageGetMessages(reply, user_id)
  io.println(
    "🔄 MASTER ENGINE forwarding direct messages retrieval to DirectMessageActor for: "
    <> user_id,
  )
  let _ = process.send(state.direct_message_actor, dm_message)
  io.println("Direct messages retrieval request sent to DirectMessageActor")
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
