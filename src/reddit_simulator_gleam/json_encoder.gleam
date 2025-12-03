import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import reddit_simulator_gleam/simulation_types.{
  type Comment, type CommentTree, type DirectMessage, type FeedObject, type Post,
  type Subreddit, type SubredditWithMembers, type UpvoteData, type User,
}

// Simple JSON encoding (basic implementation)
pub fn encode_user(user: User) -> String {
  "{\"id\":\"" <> user.id <> "\"}"
}

pub fn encode_subreddit(subreddit: Subreddit) -> String {
  "{\"id\":\""
  <> subreddit.id
  <> "\",\"name\":\""
  <> subreddit.name
  <> "\",\"description\":\""
  <> subreddit.description
  <> "\",\"created_at\":"
  <> int.to_string(subreddit.created_at)
  <> ",\"subscriber_count\":"
  <> int.to_string(subreddit.subscriber_count)
  <> ",\"moderator_ids\":"
  <> encode_string_list(subreddit.moderator_ids)
  <> "}"
}

pub fn encode_subreddit_with_members(
  subreddit_with_members: SubredditWithMembers,
) -> String {
  "{\"subreddit\":"
  <> encode_subreddit(subreddit_with_members.subreddit)
  <> ",\"member_ids\":"
  <> encode_string_list(subreddit_with_members.member_ids)
  <> "}"
}

pub fn encode_post(post: Post) -> String {
  "{\"id\":\""
  <> post.id
  <> "\",\"title\":\""
  <> escape_json_string(post.title)
  <> "\",\"content\":\""
  <> escape_json_string(post.content)
  <> "\",\"author_id\":\""
  <> post.author_id
  <> "\",\"subreddit_id\":\""
  <> post.subreddit_id
  <> "\",\"created_at\":"
  <> int.to_string(post.created_at)
  <> ",\"score\":"
  <> int.to_string(post.score)
  <> ",\"upvotes\":"
  <> int.to_string(post.upvotes)
  <> ",\"downvotes\":"
  <> int.to_string(post.downvotes)
  <> ",\"comment_count\":"
  <> int.to_string(post.comment_count)
  <> "}"
}

pub fn encode_comment(comment: Comment) -> String {
  "{\"id\":\""
  <> comment.id
  <> "\",\"content\":\""
  <> escape_json_string(comment.content)
  <> "\",\"author_id\":\""
  <> comment.author_id
  <> "\",\"subreddit_id\":\""
  <> comment.subreddit_id
  <> "\",\"parent_comment_id\":"
  <> encode_option_string(comment.parent_comment_id)
  <> ",\"created_at\":"
  <> int.to_string(comment.created_at)
  <> ",\"score\":"
  <> int.to_string(comment.score)
  <> ",\"upvotes\":"
  <> int.to_string(comment.upvotes)
  <> ",\"downvotes\":"
  <> int.to_string(comment.downvotes)
  <> ",\"depth\":"
  <> int.to_string(comment.depth)
  <> ",\"replies\":"
  <> encode_string_list(comment.replies)
  <> "}"
}

pub fn encode_comment_tree(comment_tree: CommentTree) -> String {
  "{\"root_comments\":"
  <> encode_string_list(comment_tree.root_comments)
  <> ",\"comments\":{"
  <> encode_comment_dict(comment_tree.comments)
  <> "}}"
}

pub fn encode_direct_message(dm: DirectMessage) -> String {
  "{\"id\":\""
  <> dm.id
  <> "\",\"sender_id\":\""
  <> dm.sender_id
  <> "\",\"recipient_id\":\""
  <> dm.recipient_id
  <> "\",\"content\":\""
  <> escape_json_string(dm.content)
  <> "\",\"created_at\":"
  <> int.to_string(dm.created_at)
  <> "}"
}

pub fn encode_feed_object(feed: FeedObject) -> String {
  "{\"title\":\""
  <> escape_json_string(feed.title)
  <> "\",\"content\":\""
  <> escape_json_string(feed.content)
  <> "\"}"
}

pub fn encode_upvote_data(upvote: UpvoteData) -> String {
  "{\"upvotes\":"
  <> int.to_string(upvote.upvotes)
  <> ",\"downvotes\":"
  <> int.to_string(upvote.downvotes)
  <> ",\"karma\":"
  <> int.to_string(upvote.karma)
  <> "}"
}

// Helper functions
fn encode_string_list(strings: List(String)) -> String {
  "["
  <> string.join(
    list.map(strings, fn(s) { "\"" <> escape_json_string(s) <> "\"" }),
    ",",
  )
  <> "]"
}

fn encode_option_string(opt: option.Option(String)) -> String {
  case opt {
    option.None -> "null"
    option.Some(s) -> "\"" <> escape_json_string(s) <> "\""
  }
}

fn encode_comment_dict(comments: dict.Dict(String, Comment)) -> String {
  let pairs =
    list.map(dict.to_list(comments), fn(pair) {
      case pair {
        #(key, comment) ->
          "\"" <> escape_json_string(key) <> "\":" <> encode_comment(comment)
      }
    })
  string.join(pairs, ",")
}

fn escape_json_string(s: String) -> String {
  string.replace(
    string.replace(string.replace(s, "\\", "\\\\"), "\"", "\\\""),
    "\n",
    "\\n",
  )
}

pub fn encode_list_posts(posts: List(Post)) -> String {
  "[" <> string.join(list.map(posts, encode_post), ",") <> "]"
}

pub fn encode_list_direct_messages(messages: List(DirectMessage)) -> String {
  "[" <> string.join(list.map(messages, encode_direct_message), ",") <> "]"
}

pub fn encode_list_feed_objects(feeds: List(FeedObject)) -> String {
  "[" <> string.join(list.map(feeds, encode_feed_object), ",") <> "]"
}
