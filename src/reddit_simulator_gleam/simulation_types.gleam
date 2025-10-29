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
    subreddit_id: String,
    parent_comment_id: Option(String),
    created_at: Int,
    score: Int,
    upvotes: Int,
    downvotes: Int,
    depth: Int,
    replies: List(String),
    // List of child comment IDs
  )
}

// Hierarchical comment tree for subreddit comments
pub type CommentTree {
  CommentTree(
    root_comments: List(String),
    // Top-level comment IDs
    comments: Dict(String, Comment),
    // comment_id -> Comment
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

pub type UpvoteData {
  UpvoteData(upvotes: Int, downvotes: Int, karma: Int)
}

pub type DirectMessage {
  DirectMessage(
    id: String,
    sender_id: String,
    recipient_id: String,
    content: String,
    created_at: Int,
  )
}

pub type FeedItem {
  FeedItem(post: Post, subreddit_name: String, author_username: String)
}

pub type FeedObject {
  FeedObject(title: String, content: String)
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
    peak_response_time_ms: Int,
    operations_per_second: Float,
    memory_usage_mb: Float,
    cpu_usage_percent: Float,
    network_latency_ms: Float,
    error_rate: Float,
    throughput_mbps: Float,
    concurrent_users: Int,
    active_connections: Int,
    queue_length: Int,
    cache_hit_rate: Float,
    database_queries_per_second: Float,
  )
}

pub type UserAction {
  CreatePostAction(title: String, content: String, subreddit_id: String)
  CreateCommentAction(
    content: String,
    subreddit_id: String,
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
