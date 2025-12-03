# Reddit Simulator REST API - Complete Demo Guide

This guide demonstrates all available functionality of the Reddit Simulator REST API with practical examples.

**Prerequisites:** The REST API server must be running on `http://localhost:8080`

## Table of Contents
1. [User Management](#user-management)
2. [Subreddit Management](#subreddit-management)
3. [Post Management](#post-management)
4. [Comment Management](#comment-management)
5. [Voting](#voting)
6. [Subscriptions](#subscriptions)
7. [Feed](#feed)
8. [Direct Messages](#direct-messages)
9. [Viewing Existing Data](#viewing-existing-data)

---

## User Management

### 1. Register a New User

```powershell
$response = Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"alice","email":"alice@example.com"}' -ContentType "application/json"
Write-Host "User created: $($response.id)" -ForegroundColor Green
$userId1 = $response.id
```

### 2. Register Another User

```powershell
$response = Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"bob","email":"bob@example.com"}' -ContentType "application/json"
Write-Host "User created: $($response.id)" -ForegroundColor Green
$userId2 = $response.id
```

### 3. Get User Information

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/users/$userId1" -Method Get | ConvertTo-Json
```

---

## Subreddit Management

### 4. Create a Subreddit

```powershell
$body = '{"name":"programming","description":"Discussion about programming languages and software development","creatorId":"' + $userId1 + '"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/subreddits" -Method Post -Body $body -ContentType "application/json"
Write-Host "Subreddit created: $($response.id)" -ForegroundColor Green
$subredditId1 = $response.id
```

### 5. Create Another Subreddit

```powershell
$body = '{"name":"gaming","description":"Video games and gaming culture","creatorId":"' + $userId2 + '"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/subreddits" -Method Post -Body $body -ContentType "application/json"
Write-Host "Subreddit created: $($response.id)" -ForegroundColor Green
$subredditId2 = $response.id
```

### 6. Get Subreddit Information

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1" -Method Get | ConvertTo-Json
```

### 7. Get Subreddit with Members List

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/members" -Method Get | ConvertTo-Json
```

---

## Post Management

### 8. Create a Post

```powershell
$body = '{"title":"Welcome to Programming!","content":"This is my first post in the programming subreddit.","subredditId":"' + $subredditId1 + '","authorId":"' + $userId1 + '"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/posts" -Method Post -Body $body -ContentType "application/json"
Write-Host "Post created: $($response.id)" -ForegroundColor Green
$postId1 = $response.id
```

### 9. Create Another Post

```powershell
$body = '{"title":"Best Programming Language?","content":"What do you think is the best programming language in 2024?","subredditId":"' + $subredditId1 + '","authorId":"' + $userId2 + '"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/posts" -Method Post -Body $body -ContentType "application/json"
Write-Host "Post created: $($response.id)" -ForegroundColor Green
$postId2 = $response.id
```

### 10. Get Post Information

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId1" -Method Get | ConvertTo-Json
```

### 11. Get All Posts in a Subreddit

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/posts" -Method Get | ConvertTo-Json
```

---

## Comment Management

### 12. Create a Comment on a Post

```powershell
$body = '{"content":"Great post! I totally agree.","subredditId":"' + $subredditId1 + '","authorId":"' + $userId2 + '","parentCommentId":null}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/comments" -Method Post -Body $body -ContentType "application/json"
Write-Host "Comment created: $($response.id)" -ForegroundColor Green
$commentId1 = $response.id
```

### 13. Create a Nested Comment (Reply to Comment)

```powershell
$body = '{"content":"Thanks for the feedback!","subredditId":"' + $subredditId1 + '","authorId":"' + $userId1 + '","parentCommentId":"' + $commentId1 + '"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/comments" -Method Post -Body $body -ContentType "application/json"
Write-Host "Nested comment created: $($response.id)" -ForegroundColor Green
```

### 14. Get Comment Information

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/comments/$commentId1" -Method Get | ConvertTo-Json
```

### 15. Get All Comments in a Subreddit (Comment Tree)

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/comments" -Method Get | ConvertTo-Json
```

---

## Voting

### 16. Upvote a Post

```powershell
$body = '{"userId":"' + $userId2 + '","voteType":"upvote"}'
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId1/vote" -Method Post -Body $body -ContentType "application/json"
Write-Host "Upvote cast successfully" -ForegroundColor Green
```

### 17. Downvote a Post

```powershell
$body = '{"userId":"' + $userId1 + '","voteType":"downvote"}'
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId2/vote" -Method Post -Body $body -ContentType "application/json"
Write-Host "Downvote cast successfully" -ForegroundColor Green
```

### 18. Check Post Vote Counts

```powershell
Write-Host "Post 1 vote counts:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId1" -Method Get | Select-Object id, title, upvotes, downvotes | Format-Table
```

---

## Subscriptions

### 19. Subscribe to a Subreddit

```powershell
$body = '{"userId":"' + $userId2 + '"}'
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/subscribe" -Method Post -Body $body -ContentType "application/json"
Write-Host "User subscribed to subreddit" -ForegroundColor Green
```

### 20. Check Subreddit Members (After Subscription)

```powershell
Write-Host "Subreddit members:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/members" -Method Get | ConvertTo-Json
```

### 21. Unsubscribe from a Subreddit

```powershell
$body = '{"userId":"' + $userId2 + '"}'
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/unsubscribe" -Method Post -Body $body -ContentType "application/json"
Write-Host "User unsubscribed from subreddit" -ForegroundColor Green
```

---

## Feed

### 22. Get User Feed (Posts from Subscribed Subreddits)

**Note:** First, make sure the user is subscribed to at least one subreddit with posts.

```powershell
# Subscribe user to subreddit first
$body = '{"userId":"' + $userId2 + '"}'
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId1/subscribe" -Method Post -Body $body -ContentType "application/json" | Out-Null

# Get feed
Write-Host "User feed:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/feed" -Method Get | ConvertTo-Json
```

---

## Direct Messages

### 23. Send a Direct Message

```powershell
$body = '{"senderId":"' + $userId1 + '","recipientId":"' + $userId2 + '","content":"Hey Bob, want to collaborate on a project?"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/messages" -Method Post -Body $body -ContentType "application/json"
Write-Host "Direct message sent: $($response.id)" -ForegroundColor Green
```

### 24. Send Another Direct Message (Reply)

```powershell
$body = '{"senderId":"' + $userId2 + '","recipientId":"' + $userId1 + '","content":"Sure! That sounds great. What did you have in mind?"}'
$response = Invoke-RestMethod -Uri "http://localhost:8080/messages" -Method Post -Body $body -ContentType "application/json"
Write-Host "Direct message sent: $($response.id)" -ForegroundColor Green
```

### 25. Get All Direct Messages for a User

```powershell
Write-Host "Direct messages for user $userId1:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/users/$userId1/messages" -Method Get | ConvertTo-Json
```

---

## Viewing Existing Data

### 26. View All Posts in a Subreddit

If you've seeded data using the seeding scripts, you can view existing posts:

```powershell
# Replace with an actual subreddit ID from your seeded data
$subredditId = "subreddit_1"  # Change this to an actual subreddit ID
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/posts" -Method Get | ConvertTo-Json
```

### 27. View All Comments in a Subreddit

```powershell
$subredditId = "subreddit_1"  # Change this to an actual subreddit ID
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/comments" -Method Get | ConvertTo-Json
```

### 28. View a Specific Post with All Details

```powershell
# Replace with an actual post ID from your seeded data
$postId = "post_1"  # Change this to an actual post ID
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId" -Method Get | ConvertTo-Json
```

### 29. View Subreddit with Full Member List

```powershell
$subredditId = "subreddit_1"  # Change this to an actual subreddit ID
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/members" -Method Get | ConvertTo-Json
```

### 30. Get User Information

```powershell
# Replace with an actual user ID from your seeded data
$userId = "user_1"  # Change this to an actual user ID
Invoke-RestMethod -Uri "http://localhost:8080/users/$userId" -Method Get | ConvertTo-Json
```

---

## Complete Workflow Example

Here's a complete workflow that demonstrates the full functionality:

```powershell
# Step 1: Create users
Write-Host "=== Creating Users ===" -ForegroundColor Yellow
$user1 = (Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"demo_user1","email":"demo1@example.com"}' -ContentType "application/json").id
$user2 = (Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body '{"username":"demo_user2","email":"demo2@example.com"}' -ContentType "application/json").id
Write-Host "Created users: $user1, $user2" -ForegroundColor Green

# Step 2: Create subreddit
Write-Host "`n=== Creating Subreddit ===" -ForegroundColor Yellow
$subreddit = (Invoke-RestMethod -Uri "http://localhost:8080/subreddits" -Method Post -Body ('{"name":"demo_subreddit","description":"Demo subreddit","creatorId":"' + $user1 + '"}') -ContentType "application/json")
$subredditId = $subreddit.id
Write-Host "Created subreddit: $subredditId" -ForegroundColor Green

# Step 3: Subscribe user2 to subreddit
Write-Host "`n=== Subscribing User ===" -ForegroundColor Yellow
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/subscribe" -Method Post -Body ('{"userId":"' + $user2 + '"}') -ContentType "application/json" | Out-Null
Write-Host "User subscribed" -ForegroundColor Green

# Step 4: Create post
Write-Host "`n=== Creating Post ===" -ForegroundColor Yellow
$post = (Invoke-RestMethod -Uri "http://localhost:8080/posts" -Method Post -Body ('{"title":"Demo Post","content":"This is a demo post","subredditId":"' + $subredditId + '","authorId":"' + $user1 + '"}') -ContentType "application/json")
$postId = $post.id
Write-Host "Created post: $postId" -ForegroundColor Green

# Step 5: Vote on post
Write-Host "`n=== Voting on Post ===" -ForegroundColor Yellow
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId/vote" -Method Post -Body ('{"userId":"' + $user2 + '","voteType":"upvote"}') -ContentType "application/json" | Out-Null
Write-Host "Vote cast" -ForegroundColor Green

# Step 6: Create comment
Write-Host "`n=== Creating Comment ===" -ForegroundColor Yellow
$comment = (Invoke-RestMethod -Uri "http://localhost:8080/comments" -Method Post -Body ('{"content":"Great post!","subredditId":"' + $subredditId + '","authorId":"' + $user2 + '","parentCommentId":null}') -ContentType "application/json")
Write-Host "Created comment: $($comment.id)" -ForegroundColor Green

# Step 7: Send direct message
Write-Host "`n=== Sending Direct Message ===" -ForegroundColor Yellow
Invoke-RestMethod -Uri "http://localhost:8080/messages" -Method Post -Body ('{"senderId":"' + $user1 + '","recipientId":"' + $user2 + '","content":"Hello from the demo!"}') -ContentType "application/json" | Out-Null
Write-Host "Message sent" -ForegroundColor Green

# Step 8: View results
Write-Host "`n=== Viewing Results ===" -ForegroundColor Yellow
Write-Host "`nPost details:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/posts/$postId" -Method Get | Select-Object id, title, upvotes, downvotes | Format-Table

Write-Host "`nSubreddit members:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/members" -Method Get | ConvertTo-Json

Write-Host "`nAll posts in subreddit:" -ForegroundColor Cyan
Invoke-RestMethod -Uri "http://localhost:8080/subreddits/$subredditId/posts" -Method Get | ConvertTo-Json

Write-Host "`n=== Demo Complete ===" -ForegroundColor Green
```

---

## Tips

1. **Save IDs**: When creating resources, save the returned IDs to variables (as shown in the examples) so you can use them in subsequent requests.

2. **Viewing Seeded Data**: If you've used the seeding scripts (`create_users.ps1`, `create_subreddits.ps1`, etc.), you can view that data by using the IDs that were created. The scripts typically create resources with predictable IDs like `user_1`, `user_2`, `subreddit_1`, etc.

3. **JSON Formatting**: Use `ConvertTo-Json` or `| ConvertTo-Json` to format responses for better readability.

4. **Error Handling**: If you get an error, check:
   - The server is running on port 8080
   - The resource IDs you're using actually exist
   - The JSON in your request body is valid

5. **Testing Workflow**: Run the "Complete Workflow Example" above to see all features working together in sequence.

---

## Quick Reference

| Action | Method | Endpoint | Body Required |
|--------|--------|----------|---------------|
| Register User | POST | `/users` | Yes |
| Get User | GET | `/users/{userId}` | No |
| Create Subreddit | POST | `/subreddits` | Yes |
| Get Subreddit | GET | `/subreddits/{subredditId}` | No |
| Get Subreddit Members | GET | `/subreddits/{subredditId}/members` | No |
| Subscribe | POST | `/subreddits/{subredditId}/subscribe` | Yes |
| Unsubscribe | POST | `/subreddits/{subredditId}/unsubscribe` | Yes |
| Get Subreddit Posts | GET | `/subreddits/{subredditId}/posts` | No |
| Create Post | POST | `/posts` | Yes |
| Get Post | GET | `/posts/{postId}` | No |
| Vote on Post | POST | `/posts/{postId}/vote` | Yes |
| Create Comment | POST | `/comments` | Yes |
| Get Comment | GET | `/comments/{commentId}` | No |
| Get Subreddit Comments | GET | `/subreddits/{subredditId}/comments` | No |
| Get Feed | GET | `/feed` | No |
| Send Direct Message | POST | `/messages` | Yes |
| Get Direct Messages | GET | `/users/{userId}/messages` | No |

