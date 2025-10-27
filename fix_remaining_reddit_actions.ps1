# PowerShell script to fix remaining reddit_actions.gleam issues

$content = Get-Content "src/reddit_simulator_gleam/reddit_actions.gleam" -Raw

# Fix unsubscribe function
$content = $content -replace '          Ok\(new_state\)\r\n        }\r\n      }\r\n    }\r\n    #\(Error\(_\), _\) -> Error\("User not found: " <> user_id\)\r\n    #\(_, Error\(_\)\) -> Error\("Subreddit not found: " <> subreddit_id\)\r\n  }\r\n}\r\n\r\n// ============================================================================\r\n// POST MANAGEMENT ACTIONS', '          let _ = actor.send(reply, Success("Unsubscribed from subreddit"))\n          Ok(new_state)\n        }\n      }\n    }\n    #(Error(_), _) -> {\n      let _ = actor.send(reply, Error("User not found"))\n      Error("User not found: " <> user_id)\n    }\n    #(_, Error(_)) -> {\n      let _ = actor.send(reply, Error("Subreddit not found"))\n      Error("Subreddit not found: " <> subreddit_id)\n    }\n  }\n}\n\n// ============================================================================\n// POST MANAGEMENT ACTIONS'

# Fix create_post function
$content = $content -replace '        False -> Error\("User not subscribed to subreddit"\)', '        False -> {\n          let _ = actor.send(reply, Error("User not subscribed to subreddit"))\n          Error("User not subscribed to subreddit")\n        }'

$content = $content -replace '          Ok\(new_state\)\r\n        }\r\n      }\r\n    }\r\n    #\(Error\(_\), _\) -> Error\("Author not found: " <> author_id\)\r\n    #\(_, Error\(_\)\) -> Error\("Subreddit not found: " <> subreddit_id\)\r\n  }\r\n}\r\n\r\n// ============================================================================\r\n// COMMENT MANAGEMENT ACTIONS', '          let _ = actor.send(reply, PostCreated(new_post))\n          Ok(new_state)\n        }\n      }\n    }\n    #(Error(_), _) -> {\n      let _ = actor.send(reply, Error("Author not found"))\n      Error("Author not found: " <> author_id)\n    }\n    #(_, Error(_)) -> {\n      let _ = actor.send(reply, Error("Subreddit not found"))\n      Error("Subreddit not found: " <> subreddit_id)\n    }\n  }\n}\n\n// ============================================================================\n// COMMENT MANAGEMENT ACTIONS'

# Fix create_comment function
$content = $content -replace '      Ok\(new_state\)\r\n    }\r\n    #\(Error\(_\), _\) -> Error\("Author not found: " <> author_id\)\r\n    #\(_, Error\(_\)\) -> Error\("Post not found: " <> post_id\)\r\n  }\r\n}\r\n\r\n// ============================================================================\r\n// VOTING ACTIONS', '      let _ = actor.send(reply, CommentCreated(new_comment))\n      Ok(new_state)\n    }\n    #(Error(_), _) -> {\n      let _ = actor.send(reply, Error("Author not found"))\n      Error("Author not found: " <> author_id)\n    }\n    #(_, Error(_)) -> {\n      let _ = actor.send(reply, Error("Post not found"))\n      Error("Post not found: " <> post_id)\n    }\n  }\n}\n\n// ============================================================================\n// VOTING ACTIONS'

# Fix vote_on_post function
$content = $content -replace '          Ok\(new_state\)\r\n        }\r\n        Error\(_\) -> Error\("Post author not found"\)\r\n      }\r\n    }\r\n    Error\(_\) -> Error\("Post not found: " <> post_id\)\r\n  }\r\n}\r\n\r\n/// Vote on a comment', '          let _ = actor.send(reply, Success("Vote recorded"))\n          Ok(new_state)\n        }\n        Error(_) -> {\n          let _ = actor.send(reply, Error("Post author not found"))\n          Error("Post author not found")\n        }\n      }\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, Error("Post not found"))\n      Error("Post not found: " <> post_id)\n    }\n  }\n}\n\n/// Vote on a comment'

# Fix vote_on_comment function
$content = $content -replace '          Ok\(new_state\)\r\n        }\r\n        Error\(_\) -> Error\("Comment author not found"\)\r\n      }\r\n    }\r\n    Error\(_\) -> Error\("Comment not found: " <> comment_id\)\r\n  }\r\n}\r\n\r\n// ============================================================================\r\n// MESSAGING ACTIONS', '          let _ = actor.send(reply, Success("Vote recorded"))\n          Ok(new_state)\n        }\n        Error(_) -> {\n          let _ = actor.send(reply, Error("Comment author not found"))\n          Error("Comment author not found")\n        }\n      }\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, Error("Comment not found"))\n      Error("Comment not found: " <> comment_id)\n    }\n  }\n}\n\n// ============================================================================\n// MESSAGING ACTIONS'

# Fix send_direct_message function
$content = $content -replace '      Ok\(new_state\)\r\n    }\r\n    #\(Error\(_\), _\) -> Error\("Sender not found: " <> sender_id\)\r\n    #\(_, Error\(_\)\) -> Error\("Recipient not found: " <> recipient_id\)\r\n  }\r\n}\r\n\r\n// ============================================================================\r\n// FEED AND QUERY ACTIONS', '      let _ = actor.send(reply, Success("Message sent"))\n      Ok(new_state)\n    }\n    #(Error(_), _) -> {\n      let _ = actor.send(reply, Error("Sender not found"))\n      Error("Sender not found: " <> sender_id)\n    }\n    #(_, Error(_)) -> {\n      let _ = actor.send(reply, Error("Recipient not found"))\n      Error("Recipient not found: " <> recipient_id)\n    }\n  }\n}\n\n// ============================================================================\n// FEED AND QUERY ACTIONS'

# Fix get_feed function to include reply parameter and actor.send
$content = $content -replace 'pub fn get_feed\(\r\n  state: ActorState,\r\n  user_id: UserId,\r\n\) -> Result\(List\(Post\), String\)', 'pub fn get_feed(\n  state: ActorState,\n  user_id: UserId,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '      Ok\(feed_posts\)\r\n    }\r\n    Error\(_\) -> Error\("User not found: " <> user_id\)\r\n  }\r\n}', '      let _ = actor.send(reply, FeedReceived(feed_posts))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, Error("User not found"))\n      Error("User not found: " <> user_id)\n    }\n  }\n}'

# Fix get_direct_messages function
$content = $content -replace 'pub fn get_direct_messages\(\r\n  state: ActorState,\r\n  user_id: UserId,\r\n\) -> Result\(List\(DirectMessage\), String\)', 'pub fn get_direct_messages(\n  state: ActorState,\n  user_id: UserId,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '      Ok\(messages\)\r\n    }\r\n    Error\(_\) -> Ok\(\[\]\)\r\n  }\r\n}', '      let _ = actor.send(reply, DirectMessagesReceived(messages))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, DirectMessagesReceived([]))\n      Ok(state)\n    }\n  }\n}'

# Fix get_subreddit_posts function
$content = $content -replace 'pub fn get_subreddit_posts\(\r\n  state: ActorState,\r\n  subreddit_id: SubredditId,\r\n  limit: Int,\r\n\) -> Result\(List\(Post\), String\)', 'pub fn get_subreddit_posts(\n  state: ActorState,\n  subreddit_id: SubredditId,\n  limit: Int,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '      Ok\(posts\)\r\n    }\r\n    Error\(_\) -> Ok\(\[\]\)\r\n  }\r\n}', '      let _ = actor.send(reply, SubredditPostsReceived(posts))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, SubredditPostsReceived([]))\n      Ok(state)\n    }\n  }\n}'

# Fix get_post_comments function
$content = $content -replace 'pub fn get_post_comments\(\r\n  state: ActorState,\r\n  post_id: PostId,\r\n\) -> Result\(List\(Comment\), String\)', 'pub fn get_post_comments(\n  state: ActorState,\n  post_id: PostId,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '      Ok\(comments\)\r\n    }\r\n    Error\(_\) -> Ok\(\[\]\)\r\n  }\r\n}', '      let _ = actor.send(reply, PostCommentsReceived(comments))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, PostCommentsReceived([]))\n      Ok(state)\n    }\n  }\n}'

# Fix get_subreddit_info function
$content = $content -replace 'pub fn get_subreddit_info\(\r\n  state: ActorState,\r\n  subreddit_id: SubredditId,\r\n\) -> Result\(Subreddit, String\)', 'pub fn get_subreddit_info(\n  state: ActorState,\n  subreddit_id: SubredditId,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '    Ok\(subreddit\) -> Ok\(subreddit\)\r\n    Error\(_\) -> Error\("Subreddit not found: " <> subreddit_id\)\r\n  }\r\n}', '    Ok(subreddit) -> {\n      let _ = actor.send(reply, SubredditInfoReceived(subreddit))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, Error("Subreddit not found"))\n      Error("Subreddit not found: " <> subreddit_id)\n    }\n  }\n}'

# Fix get_user_profile function
$content = $content -replace 'pub fn get_user_profile\(\r\n  state: ActorState,\r\n  user_id: UserId,\r\n\) -> Result\(User, String\)', 'pub fn get_user_profile(\n  state: ActorState,\n  user_id: UserId,\n  reply: process.Subject(ActorMessage),\n) -> Result(ActorState, String)'

$content = $content -replace '    Ok\(user\) -> Ok\(user\)\r\n    Error\(_\) -> Error\("User not found: " <> user_id\)\r\n  }\r\n}', '    Ok(user) -> {\n      let _ = actor.send(reply, UserProfileReceived(user))\n      Ok(state)\n    }\n    Error(_) -> {\n      let _ = actor.send(reply, Error("User not found"))\n      Error("User not found: " <> user_id)\n    }\n  }\n}'

Set-Content "src/reddit_simulator_gleam/reddit_actions.gleam" $content

Write-Host "Fixed remaining reddit_actions.gleam issues"

