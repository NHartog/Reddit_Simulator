function Run-Tests {
    $baseUrl = "http://localhost:8080"
    
    Write-Host "=== Testing Reddit Simulator REST API ===" -ForegroundColor Green
    Write-Host ""
    
    # 1. Register user
    Write-Host "1. Registering user..." -ForegroundColor Yellow
    try {
        $user1 = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body '{"username":"alice","email":"alice@example.com"}' -ContentType "application/json" -ErrorAction Stop | Out-Null
        $user1 = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body '{"username":"alice","email":"alice@example.com"}' -ContentType "application/json" -ErrorAction Stop
        $userId = $user1.id
        Write-Host "   ✓ User registered: $userId" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # 2. Get user
    Write-Host "2. Getting user..." -ForegroundColor Yellow
    try {
        $user = Invoke-RestMethod -Uri "$baseUrl/users/$userId" -Method Get -ErrorAction Stop | Out-Null
        $user = Invoke-RestMethod -Uri "$baseUrl/users/$userId" -Method Get -ErrorAction Stop
        Write-Host "   ✓ User retrieved: $($user.id)" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 3. Create subreddit
    Write-Host "3. Creating subreddit..." -ForegroundColor Yellow
    try {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $subredditName = "test_$timestamp"
        $body = "{`"name`":`"$subredditName`",`"description`":`"Test subreddit`",`"creatorId`":`"$userId`"}"
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        $subredditId = $subreddit.id
        Write-Host "   ✓ Subreddit created: $subredditId" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # 4. Get subreddit
    Write-Host "4. Getting subreddit..." -ForegroundColor Yellow
    try {
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId" -Method Get -ErrorAction Stop | Out-Null
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId" -Method Get -ErrorAction Stop
        Write-Host "   ✓ Subreddit retrieved: $($subreddit.name)" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 5. Get subreddit with members
    Write-Host "5. Getting subreddit with members..." -ForegroundColor Yellow
    try {
        $null = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/members" -Method Get -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Subreddit with members retrieved" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 6. Subscribe
    Write-Host "6. Subscribing to subreddit..." -ForegroundColor Yellow
    try {
        $body = "{`"userId`":`"$userId`"}"
        $null = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/subscribe" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Subscribed successfully" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 7. Create post
    Write-Host "7. Creating post..." -ForegroundColor Yellow
    try {
        $body = "{`"title`":`"Hello World`",`"content`":`"This is my first post!`",`"subredditId`":`"$subredditId`",`"authorId`":`"$userId`"}"
        $post = Invoke-RestMethod -Uri "$baseUrl/posts" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        $post = Invoke-RestMethod -Uri "$baseUrl/posts" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        $postId = $post.id
        Write-Host "   ✓ Post created: $postId" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # 8. Get post
    Write-Host "8. Getting post..." -ForegroundColor Yellow
    try {
        $post = Invoke-RestMethod -Uri "$baseUrl/posts/$postId" -Method Get -ErrorAction Stop | Out-Null
        $post = Invoke-RestMethod -Uri "$baseUrl/posts/$postId" -Method Get -ErrorAction Stop
        Write-Host "   ✓ Post retrieved: $($post.title)" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 9. Vote on post
    Write-Host "9. Voting on post..." -ForegroundColor Yellow
    try {
        $body = "{`"userId`":`"$userId`",`"voteType`":`"upvote`"}"
        $null = Invoke-RestMethod -Uri "$baseUrl/posts/$postId/vote" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Vote cast successfully" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 10. Get subreddit posts
    Write-Host "10. Getting subreddit posts..." -ForegroundColor Yellow
    try {
        $posts = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/posts" -Method Get -ErrorAction Stop | Out-Null
        $posts = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/posts" -Method Get -ErrorAction Stop
        $count = if ($posts -is [array]) { $posts.Count } else { 1 }
        Write-Host "   ✓ Retrieved $count posts" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 11. Create comment
    Write-Host "11. Creating comment..." -ForegroundColor Yellow
    try {
        $body = "{`"content`":`"Great post!`",`"subredditId`":`"$subredditId`",`"authorId`":`"$userId`",`"parentCommentId`":null}"
        $comment = Invoke-RestMethod -Uri "$baseUrl/comments" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        $comment = Invoke-RestMethod -Uri "$baseUrl/comments" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        $commentId = $comment.id
        Write-Host "   ✓ Comment created: $commentId" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 12. Get comment
    Write-Host "12. Getting comment..." -ForegroundColor Yellow
    try {
        $null = Invoke-RestMethod -Uri "$baseUrl/comments/$commentId" -Method Get -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Comment retrieved" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 13. Get subreddit comments
    Write-Host "13. Getting subreddit comments..." -ForegroundColor Yellow
    try {
        $comments = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/comments" -Method Get -ErrorAction Stop | Out-Null
        $comments = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/comments" -Method Get -ErrorAction Stop
        $count = if ($comments -is [array]) { $comments.Count } else { 1 }
        Write-Host "   ✓ Retrieved $count comments" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 14. Get feed
    Write-Host "14. Getting feed..." -ForegroundColor Yellow
    try {
        $feed = Invoke-RestMethod -Uri "$baseUrl/feed" -Method Get -ErrorAction Stop | Out-Null
        $feed = Invoke-RestMethod -Uri "$baseUrl/feed" -Method Get -ErrorAction Stop
        $count = if ($feed -is [array]) { $feed.Count } else { 1 }
        Write-Host "   ✓ Feed retrieved: $count items" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 15. Register second user
    Write-Host "15. Registering second user..." -ForegroundColor Yellow
    try {
        $user2 = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body '{"username":"bob","email":"bob@example.com"}' -ContentType "application/json" -ErrorAction Stop | Out-Null
        $user2 = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body '{"username":"bob","email":"bob@example.com"}' -ContentType "application/json" -ErrorAction Stop
        $userId2 = $user2.id
        Write-Host "   ✓ User registered: $userId2" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    # 16. Send direct message
    Write-Host "16. Sending direct message..." -ForegroundColor Yellow
    try {
        $body = '{"senderId":"' + $userId + '","receiverId":"' + $userId2 + '","content":"Hello Bob!"}'
        $null = Invoke-RestMethod -Uri "$baseUrl/messages" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Message sent successfully" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 17. Get direct messages
    Write-Host "17. Getting direct messages..." -ForegroundColor Yellow
    try {
        $messages = Invoke-RestMethod -Uri "$baseUrl/users/$userId/messages" -Method Get -ErrorAction Stop | Out-Null
        $messages = Invoke-RestMethod -Uri "$baseUrl/users/$userId/messages" -Method Get -ErrorAction Stop
        $count = if ($messages -is [array]) { $messages.Count } else { 1 }
        Write-Host "   ✓ Retrieved $count messages" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    # 18. Unsubscribe
    Write-Host "18. Unsubscribing from subreddit..." -ForegroundColor Yellow
    try {
        $body = "{`"userId`":`"$userId`"}"
        $null = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/unsubscribe" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "   ✓ Unsubscribed successfully" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=== All tests completed! ===" -ForegroundColor Green
}

# Run the tests
Run-Tests | Out-Null
