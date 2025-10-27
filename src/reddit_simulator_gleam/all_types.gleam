import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/option.{type Option}

// =============================================================================
// CORE DATA TYPES
// =============================================================================
// These are the fundamental domain models used throughout the system

pub type User {
  User(id: String)
}

pub type Subreddit {
  Subreddit(
    id: String,
    name: String,
    description: String,
    created_at: Int,
    subscriber_count: Int,
    moderator_ids: List(String),
  )
}

pub type SubredditWithMembers {
  SubredditWithMembers(subreddit: Subreddit, member_ids: List(String))
}

pub type Post {
  Post(
    id: String,
    title: String,
    content: String,
    author_id: String,
    subreddit_id: String,
    created_at: Int,
    score: Int,
    upvotes: Int,
    downvotes: Int,
    comment_count: Int,
  )
}

pub type Comment {
  Comment(
    id: String,
    content: String,
    author_id: String,
    post_id: String,
    parent_comment_id: Option(String),
    created_at: Int,
    score: Int,
    upvotes: Int,
    downvotes: Int,
    depth: Int,
  )
}

pub type Vote {
  Vote(
    id: String,
    user_id: String,
    target_id: String,
    target_type: VoteTarget,
    vote_type: VoteType,
    created_at: Int,
  )
}

pub type VoteTarget {
  PostTarget
  CommentTarget
}

pub type VoteType {
  Upvote
  Downvote
}

pub type DirectMessage {
  DirectMessage(
    id: String,
    sender_id: String,
    recipient_id: String,
    content: String,
    created_at: Int,
    is_read: Bool,
  )
}

pub type FeedItem {
  FeedItem(post: Post, subreddit_name: String, author_username: String)
}

// HTTP-style status codes for actor responses
pub type StatusCode {
  Status200
  // Success
  Status404
  // Not Found
  Status500
  // Internal Server Error
}

pub fn status_code_to_string(code: StatusCode) -> String {
  case code {
    Status200 -> "200"
    Status404 -> "404"
    Status500 -> "500"
  }
}

// =============================================================================
// CLIENT/SIMULATOR TYPES
// =============================================================================
// Types used by the simulation system and client applications

pub type SimulationConfig {
  SimulationConfig(
    num_users: Int,
    num_subreddits: Int,
    simulation_duration_ms: Int,
    zipf_alpha: Float,
    connection_probability: Float,
    post_frequency: Float,
    comment_frequency: Float,
    vote_frequency: Float,
    message_frequency: Float,
    high_activity_threshold: Int,
    max_posts_per_user: Int,
    max_comments_per_user: Int,
    repost_probability: Float,
    enable_real_time_stats: Bool,
    stats_update_interval_ms: Int,
    actor_timeout_ms: Int,
    max_concurrent_operations: Int,
  )
}

pub type SimulationState {
  SimulationState(
    config: SimulationConfig,
    start_time: Int,
    end_time: Int,
    is_running: Bool,
    master_engine_pid: Option(process.Pid),
    user_actors: Dict(String, process.Pid),
    performance_metrics: PerformanceMetrics,
  )
}

pub type PerformanceMetrics {
  PerformanceMetrics(
    total_operations: Int,
    successful_operations: Int,
    failed_operations: Int,
    average_response_time_ms: Float,
    operations_per_second: Float,
    user_activity_distribution: Dict(String, Int),
    subreddit_popularity: Dict(String, Int),
    error_rate: Float,
    memory_usage_mb: Float,
    cpu_usage_percent: Float,
    network_throughput_mbps: Float,
    zipf_distribution_accuracy: Float,
    concurrent_operations: Int,
    peak_concurrent_operations: Int,
    average_concurrent_operations: Float,
    total_simulation_time_ms: Int,
    user_connection_events: Int,
    user_disconnection_events: Int,
    posts_created: Int,
    comments_created: Int,
    votes_cast: Int,
    messages_sent: Int,
    reposts_created: Int,
    subreddit_joins: Int,
    subreddit_leaves: Int,
    feed_requests: Int,
    direct_message_requests: Int,
  )
}

pub type UserMessage {
  StartSimulation(config: SimulationConfig)
  PerformAction(action: UserAction)
  Connect
  Disconnect
  StopSimulation
}

pub type UserAction {
  CreatePostAction(title: String, content: String, subreddit_id: String)
  CreateCommentAction(
    content: String,
    post_id: String,
    parent_comment_id: Option(String),
  )
  VoteOnPostAction(post_id: String, vote_type: VoteType)
  VoteOnCommentAction(comment_id: String, vote_type: VoteType)
  SendDirectMessageAction(recipient_id: String, content: String)
  SubscribeToSubredditAction(subreddit_id: String)
  UnsubscribeFromSubredditAction(subreddit_id: String)
  GetFeedAction
  GetDirectMessagesAction
}

pub type UserActorState {
  UserActorState(
    user: User,
    config: SimulationConfig,
    is_connected: Bool,
    actions_performed: Int,
    last_action_time: Int,
    next_action_delay: Int,
    subscribed_subreddits: List(String),
    performance_stats: UserPerformanceStats,
    master_engine_pid: Option(process.Pid),
  )
}

pub type UserPerformanceStats {
  UserPerformanceStats(
    posts_created: Int,
    comments_created: Int,
    votes_cast: Int,
    messages_sent: Int,
    reposts_created: Int,
    subreddit_joins: Int,
    subreddit_leaves: Int,
    feed_requests: Int,
    direct_message_requests: Int,
    total_response_time_ms: Int,
    successful_operations: Int,
    failed_operations: Int,
  )
}

// =============================================================================
// ENGINE ACTOR TYPES
// =============================================================================
// Types used by the engine actors for internal communication and state management

// Master Engine Actor Types
pub type MasterEngineMessage {
  // String-based request routing
  ProcessRequest(
    reply: process.Subject(Result(String, String)),
    request_type: String,
    request_data: String,
  )

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

  // Comment management - create, get, get by post (hierarchical)
  CreateComment(
    reply: process.Subject(Result(Comment, String)),
    content: String,
    author_id: String,
    post_id: String,
    parent_comment_id: Option(String),
  )
  GetComment(
    reply: process.Subject(Result(Comment, String)),
    comment_id: String,
  )
  GetPostComments(
    reply: process.Subject(Result(List(Comment), String)),
    post_id: String,
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
  MarkMessageAsRead(
    reply: process.Subject(Result(Nil, String)),
    user_id: String,
    message_id: String,
  )

  // System management
  GetSystemStats(reply: process.Subject(Result(SystemStats, String)))
  Shutdown
}

pub type MasterEngineState {
  MasterEngineState(
    user_actor: process.Subject(UserActorMessage),
    subreddit_actor: process.Subject(SubredditActorMessage),
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
  UserEngineActorState(users: Dict(String, User), next_user_id: Int)
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
  ReqGetPostComments
  ReqVoteOnPost
  ReqVoteOnComment
  ReqGetUserFeed
  ReqSendDirectMessage
  ReqGetDirectMessages
  ReqMarkMessageAsRead
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
    "get_post_comments" -> ReqGetPostComments
    "vote_on_post" -> ReqVoteOnPost
    "vote_on_comment" -> ReqVoteOnComment
    "get_user_feed" -> ReqGetUserFeed
    "send_direct_message" -> ReqSendDirectMessage
    "get_direct_messages" -> ReqGetDirectMessages
    "mark_message_as_read" -> ReqMarkMessageAsRead
    "get_system_stats" -> ReqGetSystemStats
    _ -> ReqUnknown
  }
}
