# PowerShell script to fix reddit_actions.gleam function signatures

$content = Get-Content "src/reddit_simulator_gleam/reddit_actions.gleam" -Raw

# Fix function signatures to include reply parameter
$content = $content -replace 'pub fn register_user\(\s*state: ActorState,\s*username: String,\s*\) -> Result\(ActorState, String\)', 'pub fn register_user(state: ActorState, username: String, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn update_connection_status\(\s*state: ActorState,\s*user_id: UserId,\s*status: ConnectionStatus,\s*\) -> Result\(ActorState, String\)', 'pub fn update_connection_status(state: ActorState, user_id: UserId, status: ConnectionStatus, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn create_subreddit\(\s*state: ActorState,\s*name: String,\s*description: String,\s*creator_id: UserId,\s*\) -> Result\(ActorState, String\)', 'pub fn create_subreddit(state: ActorState, name: String, description: String, creator_id: UserId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn subscribe_to_subreddit\(\s*state: ActorState,\s*user_id: UserId,\s*subreddit_id: SubredditId,\s*\) -> Result\(ActorState, String\)', 'pub fn subscribe_to_subreddit(state: ActorState, user_id: UserId, subreddit_id: SubredditId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn unsubscribe_from_subreddit\(\s*state: ActorState,\s*user_id: UserId,\s*subreddit_id: SubredditId,\s*\) -> Result\(ActorState, String\)', 'pub fn unsubscribe_from_subreddit(state: ActorState, user_id: UserId, subreddit_id: SubredditId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn create_post\(\s*state: ActorState,\s*author_id: UserId,\s*subreddit_id: SubredditId,\s*title: String,\s*content: String,\s*\) -> Result\(ActorState, String\)', 'pub fn create_post(state: ActorState, author_id: UserId, subreddit_id: SubredditId, title: String, content: String, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn create_comment\(\s*state: ActorState,\s*author_id: UserId,\s*post_id: PostId,\s*parent_comment_id: Option\(CommentId\),\s*content: String,\s*\) -> Result\(ActorState, String\)', 'pub fn create_comment(state: ActorState, author_id: UserId, post_id: PostId, parent_comment_id: Option(CommentId), content: String, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn vote_on_post\(\s*state: ActorState,\s*user_id: UserId,\s*post_id: PostId,\s*vote: Vote,\s*\) -> Result\(ActorState, String\)', 'pub fn vote_on_post(state: ActorState, user_id: UserId, post_id: PostId, vote: Vote, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn vote_on_comment\(\s*state: ActorState,\s*user_id: UserId,\s*comment_id: CommentId,\s*vote: Vote,\s*\) -> Result\(ActorState, String\)', 'pub fn vote_on_comment(state: ActorState, user_id: UserId, comment_id: CommentId, vote: Vote, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn send_direct_message\(\s*state: ActorState,\s*sender_id: UserId,\s*recipient_id: UserId,\s*content: String,\s*\) -> Result\(ActorState, String\)', 'pub fn send_direct_message(state: ActorState, sender_id: UserId, recipient_id: UserId, content: String, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_feed\(\s*state: ActorState,\s*user_id: UserId,\s*\) -> Result\(ActorState, String\)', 'pub fn get_feed(state: ActorState, user_id: UserId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_direct_messages\(\s*state: ActorState,\s*user_id: UserId,\s*\) -> Result\(ActorState, String\)', 'pub fn get_direct_messages(state: ActorState, user_id: UserId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_subreddit_posts\(\s*state: ActorState,\s*subreddit_id: SubredditId,\s*limit: Int,\s*\) -> Result\(ActorState, String\)', 'pub fn get_subreddit_posts(state: ActorState, subreddit_id: SubredditId, limit: Int, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_post_comments\(\s*state: ActorState,\s*post_id: PostId,\s*\) -> Result\(ActorState, String\)', 'pub fn get_post_comments(state: ActorState, post_id: PostId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_subreddit_info\(\s*state: ActorState,\s*subreddit_id: SubredditId,\s*\) -> Result\(ActorState, String\)', 'pub fn get_subreddit_info(state: ActorState, subreddit_id: SubredditId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

$content = $content -replace 'pub fn get_user_profile\(\s*state: ActorState,\s*user_id: UserId,\s*\) -> Result\(ActorState, String\)', 'pub fn get_user_profile(state: ActorState, user_id: UserId, reply: process.Subject(ActorMessage)) -> Result(ActorState, String)'

Set-Content "src/reddit_simulator_gleam/reddit_actions.gleam" $content

Write-Host "Fixed function signatures in reddit_actions.gleam"

