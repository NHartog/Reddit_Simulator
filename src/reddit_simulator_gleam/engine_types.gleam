import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/option.{type Option}
import reddit_simulator_gleam/simulation_types.{
  type Comment, type CommentTree, type DirectMessage, type FeedItem,
  type FeedObject, type Post, type Subreddit, type SubredditWithMembers,
  type UpvoteData, type User, type VoteType,
}

// =============================================================================
// ENGINE ACTOR TYPES
// =============================================================================
// Types used by the engine actors for internal communication and state management

// Master Engine Actor Types
pub type MasterEngineMessage {

  // User management - only register and get
  RegisterUser(reply: process.Subject(String), username: String, email: String)
  GetUser(reply: process.Subject(String), user_id: String)

  // Subreddit management - create, get, join, leave
  CreateSubreddit(
    reply: process.Subject(Result(Subreddit, String)),
    name: String,
    description: String,
    creator_id: String,
  )
  GetSubreddit(
    reply: process.Subject(Result(Subreddit, String)),
    subreddit_id: String,
  )
  GetSubredditWithMembers(
    reply: process.Subject(Result(SubredditWithMembers, String)),
    subreddit_id: String,
  )
  SubscribeToSubreddit(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    subreddit_id: String,
  )
  UnsubscribeFromSubreddit(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    subreddit_id: String,
  )

  // Post management - create, get, get by subreddit
  CreatePost(
    reply: process.Subject(Result(Post, String)),
    title: String,
    content: String,
    author_id: String,
    subreddit_id: String,
  )
  GetPost(reply: process.Subject(Result(Post, String)), post_id: String)
  GetSubredditPosts(
    reply: process.Subject(Result(List(Post), String)),
    subreddit_id: String,
    limit: Int,
  )

  // Comment management - create, get, get by subreddit (hierarchical)
  CreateComment(
    reply: process.Subject(Result(Comment, String)),
    content: String,
    author_id: String,
    subreddit_id: String,
    parent_comment_id: Option(String),
  )
  GetComment(
    reply: process.Subject(Result(Comment, String)),
    comment_id: String,
  )
  GetSubredditComments(
    reply: process.Subject(Result(CommentTree, String)),
    subreddit_id: String,
  )

  // Voting - upvote/downvote with karma computation
  VoteOnPost(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    post_id: String,
    vote_type: VoteType,
  )
  VoteOnComment(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    comment_id: String,
    vote_type: VoteType,
  )

  // Feed - get user feed
  GetUserFeed(
    reply: process.Subject(Result(List(FeedItem), String)),
    user_id: String,
    limit: Int,
  )
  GetFeed(reply: process.Subject(Result(List(FeedObject), String)), limit: Int)

  // Direct messages - send, get, reply
  SendDirectMessage(
    reply: process.Subject(Result(DirectMessage, String)),
    sender_id: String,
    recipient_id: String,
    content: String,
  )
  GetDirectMessages(
    reply: process.Subject(Result(List(DirectMessage), String)),
    user_id: String,
  )

  // System management
  GetSystemStats(reply: process.Subject(Result(SystemStats, String)))
  Shutdown
}

pub type MasterEngineState {
  MasterEngineState(
    user_actor: process.Subject(UserActorMessage),
    subreddit_actor: process.Subject(SubredditActorMessage),
    post_actor: process.Subject(PostActorMessage),
    comment_actor: process.Subject(CommentActorMessage),
    upvote_actor: process.Subject(UpvoteActorMessage),
    feed_actor: process.Subject(FeedActorMessage),
    direct_message_actor: process.Subject(DirectMessageActorMessage),
  )
}

pub type SystemStats {
  SystemStats(
    total_users: Int,
    total_subreddits: Int,
    total_posts: Int,
    total_comments: Int,
    total_votes: Int,
    total_direct_messages: Int,
    active_users: Int,
    most_popular_subreddit: Option(String),
    most_active_user: Option(String),
  )
}

// User Actor Types - Handles user registration and management
pub type UserActorMessage {
  UserRegisterUser(
    reply: process.Subject(String),
    username: String,
    email: String,
  )
  UserGetUser(reply: process.Subject(String), user_id: String)
  UserShutdown
}

pub type UserEngineActorState {
  UserEngineActorState(
    users: Dict(String, User),
    next_user_id: Int,
    direct_message_actor: Option(process.Subject(DirectMessageActorMessage)),
  )
}

// Subreddit Actor Types - Handles subreddit creation, joining, and leaving
pub type SubredditActorMessage {
  SubredditCreateSubreddit(
    reply: process.Subject(Result(Subreddit, String)),
    name: String,
    description: String,
    creator_id: String,
  )
  SubredditJoinSubreddit(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    subreddit_id: String,
  )
  SubredditLeaveSubreddit(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    subreddit_id: String,
  )
  SubredditGetSubreddit(
    reply: process.Subject(Result(Subreddit, String)),
    subreddit_id: String,
  )
  SubredditGetSubredditWithMembers(
    reply: process.Subject(Result(SubredditWithMembers, String)),
    subreddit_id: String,
  )
  SubredditShutdown
}

pub type SubredditActorState {
  SubredditActorState(
    subreddits: Dict(String, Subreddit),
    subreddit_members: Dict(String, List(String)),
    // subreddit_id -> list of user_ids
    next_subreddit_id: Int,
    post_actor: Option(process.Subject(PostActorMessage)),
    comment_actor: Option(process.Subject(CommentActorMessage)),
  )
}

// Post Actor Types - Handles post creation, retrieval, and management
pub type PostActorMessage {
  PostCreatePost(
    reply: process.Subject(Result(Post, String)),
    title: String,
    content: String,
    author_id: String,
    subreddit_id: String,
  )
  PostGetPost(reply: process.Subject(Result(Post, String)), post_id: String)
  PostGetSubredditPosts(
    reply: process.Subject(Result(List(Post), String)),
    subreddit_id: String,
    limit: Int,
  )
  PostAddSubreddit(
    reply: process.Subject(Result(Nil, String)),
    subreddit_id: String,
  )
  PostShutdown
}

pub type PostActorState {
  PostActorState(
    posts: Dict(String, Post),
    subreddit_posts: Dict(String, List(String)),
    // subreddit_id -> list of post_ids
    next_post_id: Int,
    upvote_actor: process.Subject(UpvoteActorMessage),
    feed_actor: process.Subject(FeedActorMessage),
  )
}

// Comment Actor Types - Handles comment creation, retrieval, and hierarchical management
pub type CommentActorMessage {
  CommentCreateComment(
    reply: process.Subject(Result(Comment, String)),
    content: String,
    author_id: String,
    subreddit_id: String,
    parent_comment_id: Option(String),
  )
  CommentGetComment(
    reply: process.Subject(Result(Comment, String)),
    comment_id: String,
  )
  CommentGetSubredditComments(
    reply: process.Subject(Result(CommentTree, String)),
    subreddit_id: String,
  )
  CommentAddSubreddit(
    reply: process.Subject(Result(Nil, String)),
    subreddit_id: String,
  )
  CommentShutdown
}

pub type CommentActorState {
  CommentActorState(
    subreddit_comments: Dict(String, CommentTree),
    // subreddit_id -> CommentTree
    next_comment_id: Int,
  )
}

// Upvote Actor Types - Handles upvotes, downvotes, and karma calculations
pub type UpvoteActorMessage {
  UpvoteCreateEntry(
    reply: process.Subject(Result(Nil, String)),
    post_id: String,
  )
  UpvoteUpvote(
    reply: process.Subject(Result(UpvoteData, String)),
    post_id: String,
  )
  UpvoteDownvote(
    reply: process.Subject(Result(UpvoteData, String)),
    post_id: String,
  )
  UpvoteGetUpvote(
    reply: process.Subject(Result(UpvoteData, String)),
    post_id: String,
  )
  UpvoteShutdown
}

pub type UpvoteActorState {
  UpvoteActorState(
    upvotes: Dict(String, UpvoteData),
    // post_id -> UpvoteData
  )
}

// Feed Actor Types - Handles feed management and post aggregation
pub type FeedActorMessage {
  FeedAddPost(
    reply: process.Subject(Result(Nil, String)),
    post_id: String,
    title: String,
    content: String,
  )
  FeedGetFeed(
    reply: process.Subject(Result(List(FeedObject), String)),
    limit: Int,
  )
  FeedShutdown
}

pub type FeedActorState {
  FeedActorState(
    feed_posts: Dict(String, FeedObject),
    // post_id -> FeedObject
  )
}

// Direct Message Actor Types - Handles direct messages between users
pub type DirectMessageActorMessage {
  DirectMessageAddUser(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
  )
  DirectMessageSendMessage(
    reply: process.Subject(Result(DirectMessage, String)),
    sender_id: String,
    recipient_id: String,
    content: String,
  )
  DirectMessageGetMessages(
    reply: process.Subject(Result(List(DirectMessage), String)),
    user_id: String,
  )
  DirectMessageShutdown
}

pub type DirectMessageActorState {
  DirectMessageActorState(
    user_messages: Dict(String, List(DirectMessage)),
    // user_id -> List(DirectMessage)
    next_message_id: Int,
  )
}

// =============================================================================
// REQUEST ROUTING TYPES
// =============================================================================
// Types for string-based request routing and parsing

pub type RequestType {
  ReqCreateUser
  ReqGetUser
  ReqCreateSubreddit
  ReqGetSubreddit
  ReqSubscribeToSubreddit
  ReqUnsubscribeFromSubreddit
  ReqCreatePost
  ReqGetPost
  ReqGetSubredditPosts
  ReqCreateComment
  ReqGetComment
  ReqGetSubredditComments
  ReqVoteOnPost
  ReqVoteOnComment
  ReqGetUserFeed
  ReqSendDirectMessage
  ReqGetDirectMessages
  ReqGetSystemStats
  ReqUnknown
}

pub fn parse_request_type(request: String) -> RequestType {
  case request {
    "create_user" -> ReqCreateUser
    "get_user" -> ReqGetUser
    "create_subreddit" -> ReqCreateSubreddit
    "get_subreddit" -> ReqGetSubreddit
    "subscribe_to_subreddit" -> ReqSubscribeToSubreddit
    "unsubscribe_from_subreddit" -> ReqUnsubscribeFromSubreddit
    "create_post" -> ReqCreatePost
    "get_post" -> ReqGetPost
    "get_subreddit_posts" -> ReqGetSubredditPosts
    "create_comment" -> ReqCreateComment
    "get_comment" -> ReqGetComment
    "get_subreddit_comments" -> ReqGetSubredditComments
    "vote_on_post" -> ReqVoteOnPost
    "vote_on_comment" -> ReqVoteOnComment
    "get_user_feed" -> ReqGetUserFeed
    "send_direct_message" -> ReqSendDirectMessage
    "get_direct_messages" -> ReqGetDirectMessages
    "get_system_stats" -> ReqGetSystemStats
    _ -> ReqUnknown
  }
}
