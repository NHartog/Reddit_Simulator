$baseUrl = "http://localhost:8080"
$numUsers = 10000
$numSubreddits = 100
$postsPerSubreddit = 50
$commentsPerPost = 10

Write-Host "=== Seeding Reddit Simulator REST API ===" -ForegroundColor Green
Write-Host ""

# Create users
Write-Host "Creating $numUsers users..." -ForegroundColor Yellow
$userIds = @()
for ($i = 1; $i -le $numUsers; $i++) {
    try {
        $body = '{"username":"user' + $i + '","email":"user' + $i + '@example.com"}'
        $response = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
        $response = Invoke-RestMethod -Uri "$baseUrl/users" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        if ($response.id) {
            $userIds += $response.id
        }
        if ($i % 1000 -eq 0) {
            Write-Host "   Created $i users (successful: $($userIds.Count))..." -ForegroundColor Cyan
        }
    } catch {
        # Silently continue
    }
}
Write-Host "   ✓ Created $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

if ($userIds.Count -eq 0) {
    Write-Host "ERROR: No users were created. Cannot continue." -ForegroundColor Red
    exit 1
}

# Create subreddits
Write-Host "Creating $numSubreddits subreddits..." -ForegroundColor Yellow
$subredditIds = @()
for ($i = 1; $i -le $numSubreddits; $i++) {
    try {
        $creatorId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
        $name = "subreddit_$i"
        $body = '{"name":"' + $name + '","description":"Subreddit number ' + $i + '","creatorId":"' + $creatorId + '"}'
        $response = Invoke-RestMethod -Uri "$baseUrl/subreddits" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
        $response = Invoke-RestMethod -Uri "$baseUrl/subreddits" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        if ($response.id) {
            $subredditIds += $response.id
        }
        if ($i % 10 -eq 0) {
            Write-Host "   Created $i subreddits (successful: $($subredditIds.Count))..." -ForegroundColor Cyan
        }
    } catch {
        # Silently continue
    }
}
Write-Host "   ✓ Created $($subredditIds.Count) subreddits" -ForegroundColor Green
Write-Host ""

# Initialize variables
$postIds = @()
$postCount = 0
$commentCount = 0
$voteCount = 0
$subscriptionCount = 0

if ($subredditIds.Count -eq 0) {
    Write-Host "WARNING: No subreddits were created. Skipping posts and comments." -ForegroundColor Yellow
} else {
    # Create posts
    Write-Host "Creating posts..." -ForegroundColor Yellow
    foreach ($subredditId in $subredditIds) {
        for ($j = 1; $j -le $postsPerSubreddit; $j++) {
            try {
                $authorId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
                $title = "Post $j in $subredditId"
                $content = "This is post number $j in subreddit $subredditId"
                $body = '{"title":"' + $title + '","content":"' + $content + '","subredditId":"' + $subredditId + '","authorId":"' + $authorId + '"}'
                $response = Invoke-RestMethod -Uri "$baseUrl/posts" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
                $response = Invoke-RestMethod -Uri "$baseUrl/posts" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
                if ($response.id) {
                    $postIds += $response.id
                    $postCount++
                }
                if ($postCount % 500 -eq 0) {
                    Write-Host "   Created $postCount posts..." -ForegroundColor Cyan
                }
            } catch {
                # Silently continue
            }
        }
    }
    Write-Host "   ✓ Created $postCount posts" -ForegroundColor Green
    Write-Host ""

    # Create comments
    if ($postIds.Count -gt 0) {
        Write-Host "Creating comments..." -ForegroundColor Yellow
        $maxPosts = [Math]::Min(100, $postIds.Count)
        for ($idx = 0; $idx -lt $maxPosts; $idx++) {
            $postId = $postIds[$idx]
            $subredditId = $subredditIds[(Get-Random -Minimum 0 -Maximum $subredditIds.Count)]
            for ($k = 1; $k -le $commentsPerPost; $k++) {
                try {
                    $authorId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
                    $content = "Comment $k on post $postId"
                    $body = '{"content":"' + $content + '","subredditId":"' + $subredditId + '","authorId":"' + $authorId + '","parentCommentId":null}'
                    $null = Invoke-RestMethod -Uri "$baseUrl/comments" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
                    $commentCount++
                    if ($commentCount % 100 -eq 0) {
                        Write-Host "   Created $commentCount comments..." -ForegroundColor Cyan
                    }
                } catch {
                    # Silently continue
                }
            }
        }
        Write-Host "   ✓ Created $commentCount comments" -ForegroundColor Green
        Write-Host ""
    }

    # Create subscriptions
    Write-Host "Creating subscriptions..." -ForegroundColor Yellow
    for ($i = 1; $i -le 5000; $i++) {
        try {
            $userId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
            $subredditId = $subredditIds[(Get-Random -Minimum 0 -Maximum $subredditIds.Count)]
            $body = '{"userId":"' + $userId + '"}'
            $null = Invoke-RestMethod -Uri "$baseUrl/subreddits/$subredditId/subscribe" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
            $subscriptionCount++
            if ($i % 1000 -eq 0) {
                Write-Host "   Created $i subscriptions..." -ForegroundColor Cyan
            }
        } catch {
            # Silently continue
        }
    }
    Write-Host "   ✓ Created $subscriptionCount subscriptions" -ForegroundColor Green
    Write-Host ""

    # Create votes
    if ($postIds.Count -gt 0) {
        Write-Host "Creating votes..." -ForegroundColor Yellow
        $maxPosts = [Math]::Min(1000, $postIds.Count)
        for ($i = 1; $i -le 2000; $i++) {
            try {
                $userId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
                $postIdx = Get-Random -Minimum 0 -Maximum $maxPosts
                $postId = $postIds[$postIdx]
                $randomVal = Get-Random
                if ($randomVal % 2 -eq 0) {
                    $voteType = "upvote"
                } else {
                    $voteType = "downvote"
                }
                $body = '{"userId":"' + $userId + '","voteType":"' + $voteType + '"}'
                $null = Invoke-RestMethod -Uri "$baseUrl/posts/$postId/vote" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop 2>&1 | Out-Null
                $voteCount++
                if ($i % 500 -eq 0) {
                    Write-Host "   Created $i votes..." -ForegroundColor Cyan
                }
            } catch {
                # Silently continue
            }
        }
        Write-Host "   ✓ Created $voteCount votes" -ForegroundColor Green
        Write-Host ""
    }
}

Write-Host "=== Seeding completed! ===" -ForegroundColor Green
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  - Users: $($userIds.Count)" -ForegroundColor White
Write-Host "  - Subreddits: $($subredditIds.Count)" -ForegroundColor White
Write-Host "  - Posts: $postCount" -ForegroundColor White
Write-Host "  - Comments: $commentCount" -ForegroundColor White
Write-Host "  - Subscriptions: $subscriptionCount" -ForegroundColor White
Write-Host "  - Votes: $voteCount" -ForegroundColor White
Write-Host ""
