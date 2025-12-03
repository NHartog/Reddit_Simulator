# REST API Testing Guide

This guide provides step-by-step instructions to test all REST API endpoints.

## Prerequisites

1. Start the REST API server:
   ```powershell
   gleam run -m reddit_simulator_gleam/rest_api_main
   ```

2. Keep the server running in one terminal window.

3. Open a new PowerShell terminal for testing.

## Test Sequence

### 1. Register a User ✓ (Already tested!)

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"alice","email":"alice@example.com"}' -ContentType "application/json"
```

Expected: `{"id":"user_1"}`

### 2. Get User

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/users/user_1" -Method Get
```

Expected: `{"id":"user_1"}`

### 3. Create a Subreddit

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits" -Method Post -Body '{"name":"programming","description":"Discussion about programming","creatorId":"user_1"}' -ContentType "application/json"
```

**Important:** The subreddit ID is the same as the name! So if you create a subreddit named "programming", the ID will be "programming".

Expected: Subreddit JSON with `id: "programming"`, name, description, etc.

### 4. Get Subreddit

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming" -Method Get
```

**Note:** Use the subreddit name (not "subreddit_1") as the ID in the URL.

Expected: Subreddit JSON with id, name, description, etc.

### 5. Get Subreddit with Members

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming/members" -Method Get
```

**Note:** Use the subreddit name as the ID.

Expected: Subreddit JSON with members list

### 6. Subscribe to Subreddit

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming/subscribe" -Method Post -Body '{"userId":"user_1"}' -ContentType "application/json"
```

**Note:** Use the subreddit name as the ID.

Expected: Success response

### 7. Create a Post

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/posts" -Method Post -Body '{"title":"Hello World","content":"This is my first post!","subredditId":"programming","authorId":"user_1"}' -ContentType "application/json"
```

**Note:** Use the subreddit name as the `subredditId`.

Expected: `{"id":"post_1"}`

### 8. Get Post

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/posts/post_1" -Method Get
```

Expected: Post JSON with id, title, content, etc.

### 9. Vote on Post

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/posts/post_1/vote" -Method Post -Body '{"userId":"user_1","voteType":"upvote"}' -ContentType "application/json"
```

Expected: Success response

### 10. Get Subreddit Posts

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming/posts" -Method Get
```

**Note:** Use the subreddit name as the ID.

Expected: Array of posts

### 11. Create a Comment

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/comments" -Method Post -Body '{"content":"Great post!","subredditId":"programming","authorId":"user_1","parentCommentId":null}' -ContentType "application/json"
```

**Note:** Use the subreddit name as the `subredditId`.

Expected: `{"id":"comment_1"}`

### 12. Get Comment

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/comments/comment_1" -Method Get
```

Expected: Comment JSON

### 13. Get Subreddit Comments

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming/comments" -Method Get
```

**Note:** Use the subreddit name as the ID.

Expected: Array of comments

### 14. Get Feed

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/feed" -Method Get
```

Expected: Array of feed objects

### 15. Send Direct Message

First, register another user:
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"bob","email":"bob@example.com"}' -ContentType "application/json"
```

Then send a message:
```powershell
Invoke-RestMethod -Uri "http://localhost:8080/messages" -Method Post -Body '{"senderId":"user_1","receiverId":"user_2","content":"Hello Bob!"}' -ContentType "application/json"
```

Expected: Success response

### 16. Get Direct Messages

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/users/user_1/messages" -Method Get
```

Expected: Array of direct messages

### 17. Unsubscribe from Subreddit

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/programming/unsubscribe" -Method Post -Body '{"userId":"user_1"}' -ContentType "application/json"
```

**Note:** Use the subreddit name as the ID.

Expected: Success response

## Complete Test Script

Save this as `test_api.ps1` and run it:

```powershell
$baseUrl = "http://localhost:8080"

Write-Host "=== Testing Reddit Simulator REST API ===" -ForegroundColor Green
Write-Host ""

# 1. Register user
Write-Host "1. Registering user..." -ForegroundColor Yellow
$user1 = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body '{"username":"alice","email":"alice@example.com"}' -ContentType "application/json"
$userId = $user1.id
Write-Host "   ✓ User registered: $userId" -ForegroundColor Green

# 2. Get user
Write-Host "2. Getting user..." -ForegroundColor Yellow
$user = Invoke-RestMethod -Uri "$baseUrl/users/$userId" -Method Get
Write-Host "   ✓ User retrieved: $($user.id)" -ForegroundColor Green

# 3. Create subreddit
Write-Host "3. Creating subreddit..." -ForegroundColor Yellow
$subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits" -Method Post -Body "{\"name\":\"programming\",\"description\":\"Discussion about programming\",\"creatorId\":\"$userId\"}" -ContentType "application/json"
$subredditId = $subreddit.id
Write-Host "   ✓ Subreddit created: $subredditId" -ForegroundColor Green

# 4. Get subreddit
Write-Host "4. Getting subreddit..." -ForegroundColor Yellow
$subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId" -Method Get
Write-Host "   ✓ Subreddit retrieved: $($subreddit.name)" -ForegroundColor Green

# 5. Subscribe
Write-Host "5. Subscribing to subreddit..." -ForegroundColor Yellow
Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/subscribe" -Method Post -Body "{\"userId\":\"$userId\"}" -ContentType "application/json" | Out-Null
Write-Host "   ✓ Subscribed successfully" -ForegroundColor Green

# 6. Create post
Write-Host "6. Creating post..." -ForegroundColor Yellow
$post = Invoke-RestMethod -Uri "$baseUrl/posts" -Method Post -Body "{\"title\":\"Hello World\",\"content\":\"This is my first post!\",\"subredditId\":\"$subredditId\",\"authorId\":\"$userId\"}" -ContentType "application/json"
$postId = $post.id
Write-Host "   ✓ Post created: $postId" -ForegroundColor Green

# 7. Get post
Write-Host "7. Getting post..." -ForegroundColor Yellow
$post = Invoke-RestMethod -Uri "$baseUrl/posts/$postId" -Method Get
Write-Host "   ✓ Post retrieved: $($post.title)" -ForegroundColor Green

# 8. Vote on post
Write-Host "8. Voting on post..." -ForegroundColor Yellow
Invoke-RestMethod -Uri "$baseUrl/posts/$postId/vote" -Method Post -Body "{\"userId\":\"$userId\",\"voteType\":\"upvote\"}" -ContentType "application/json" | Out-Null
Write-Host "   ✓ Vote cast successfully" -ForegroundColor Green

# 9. Create comment
Write-Host "9. Creating comment..." -ForegroundColor Yellow
$comment = Invoke-RestMethod -Uri "$baseUrl/comments" -Method Post -Body "{\"content\":\"Great post!\",\"subredditId\":\"$subredditId\",\"authorId\":\"$userId\",\"parentCommentId\":null}" -ContentType "application/json"
$commentId = $comment.id
Write-Host "   ✓ Comment created: $commentId" -ForegroundColor Green

# 10. Get feed
Write-Host "10. Getting feed..." -ForegroundColor Yellow
$feed = Invoke-RestMethod -Uri "$baseUrl/feed" -Method Get
Write-Host "   ✓ Feed retrieved: $($feed.Count) items" -ForegroundColor Green

Write-Host ""
Write-Host "=== All tests completed! ===" -ForegroundColor Green
```

