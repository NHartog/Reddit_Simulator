# PowerShell script to fix engine_actor.gleam function calls

$content = Get-Content "src/reddit_simulator_gleam/engine_actor.gleam" -Raw

# Fix all reddit_actions function calls to include reply parameter
$content = $content -replace 'case reddit_actions\.register_user\(state, username\)', 'let reply = process.new_subject()\n  case reddit_actions.register_user(state, username, reply)'

$content = $content -replace 'case reddit_actions\.update_connection_status\(state, user_id, status, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.update_connection_status(state, user_id, status, reply)'

$content = $content -replace 'case reddit_actions\.create_subreddit\(state, name, description, creator_id, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.create_subreddit(state, name, description, creator_id, reply)'

$content = $content -replace 'case reddit_actions\.subscribe_to_subreddit\(state, user_id, subreddit_id, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.subscribe_to_subreddit(state, user_id, subreddit_id, reply)'

$content = $content -replace 'case reddit_actions\.unsubscribe_from_subreddit\(state, user_id, subreddit_id, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.unsubscribe_from_subreddit(state, user_id, subreddit_id, reply)'

$content = $content -replace 'case reddit_actions\.create_post\(state, author_id, subreddit_id, title, content, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.create_post(state, author_id, subreddit_id, title, content, reply)'

$content = $content -replace 'case reddit_actions\.get_subreddit_posts\(state, subreddit_id, limit, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.get_subreddit_posts(state, subreddit_id, limit, reply)'

$content = $content -replace 'case reddit_actions\.create_comment\(state, author_id, post_id, parent_comment_id, content, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.create_comment(state, author_id, post_id, parent_comment_id, content, reply)'

$content = $content -replace 'case reddit_actions\.get_post_comments\(state, post_id, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.get_post_comments(state, post_id, reply)'

$content = $content -replace 'case reddit_actions\.vote_on_post\(state, user_id, post_id, vote, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.vote_on_post(state, user_id, post_id, vote, reply)'

$content = $content -replace 'case reddit_actions\.vote_on_comment\(state, user_id, comment_id, vote, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.vote_on_comment(state, user_id, comment_id, vote, reply)'

$content = $content -replace 'case reddit_actions\.send_direct_message\(state, sender_id, recipient_id, content, reply\)', 'let reply = process.new_subject()\n  case reddit_actions.send_direct_message(state, sender_id, recipient_id, content, reply)'

$content = $content -replace 'case reddit_actions\.get_direct_messages\(state, user_id\)', 'let reply = process.new_subject()\n  case reddit_actions.get_direct_messages(state, user_id, reply)'

$content = $content -replace 'case reddit_actions\.get_feed\(state, user_id\)', 'let reply = process.new_subject()\n  case reddit_actions.get_feed(state, user_id, reply)'

$content = $content -replace 'case reddit_actions\.get_subreddit_info\(state, subreddit_id\)', 'let reply = process.new_subject()\n  case reddit_actions.get_subreddit_info(state, subreddit_id, reply)'

$content = $content -replace 'case reddit_actions\.get_user_profile\(state, user_id\)', 'let reply = process.new_subject()\n  case reddit_actions.get_user_profile(state, user_id, reply)'

Set-Content "src/reddit_simulator_gleam/engine_actor.gleam" $content

Write-Host "Fixed function calls in engine_actor.gleam"

