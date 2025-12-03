$baseUrl = "http://localhost:8080"
$commentsPerPost = 10
$maxPosts = 100

Write-Host "Getting existing posts..." -ForegroundColor Yellow
$postIds = @()
$postNum = 1
while ($postIds.Count -lt $maxPosts -and $postNum -le 10000) {
    try {
        $post = Invoke-RestMethod -Uri "$baseUrl/posts/post_$postNum" -Method Get -ErrorAction Stop 2>&1 | Out-Null
        $post = Invoke-RestMethod -Uri "$baseUrl/posts/post_$postNum" -Method Get -ErrorAction Stop
        if ($post.id) {
            $postIds += $post.id
        }
    } catch {
        # Post doesn't exist, skip
    }
    $postNum++
}

if ($postIds.Count -eq 0) {
    Write-Host "ERROR: No posts found. Please run create_posts.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($postIds.Count) posts" -ForegroundColor Green
Write-Host ""

Write-Host "Getting existing subreddits..." -ForegroundColor Yellow
$subredditIds = @()
for ($i = 1; $i -le 100; $i++) {
    try {
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits/subreddit_$i" -Method Get -ErrorAction Stop 2>&1 | Out-Null
        $subreddit = Invoke-RestMethod -Uri "$baseUrl/subreddits/subreddit_$i" -Method Get -ErrorAction Stop
        if ($subreddit.id) {
            $subredditIds += $subreddit.id
        }
    } catch {
        # Subreddit doesn't exist, skip
    }
}

if ($subredditIds.Count -eq 0) {
    Write-Host "ERROR: No subreddits found." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($subredditIds.Count) subreddits" -ForegroundColor Green
Write-Host ""

Write-Host "Getting existing users..." -ForegroundColor Yellow
$userIds = @()
for ($i = 1; $i -le 10000; $i++) {
    try {
        $user = Invoke-RestMethod -Uri "$baseUrl/users/user_$i" -Method Get -ErrorAction Stop 2>&1 | Out-Null
        $user = Invoke-RestMethod -Uri "$baseUrl/users/user_$i" -Method Get -ErrorAction Stop
        if ($user.id) {
            $userIds += $user.id
        }
        if ($i % 1000 -eq 0 -and $userIds.Count -gt 0) {
            break
        }
    } catch {
        # User doesn't exist, skip
    }
}

if ($userIds.Count -eq 0) {
    Write-Host "ERROR: No users found." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

Write-Host "Creating comments ($commentsPerPost per post on first $($postIds.Count) posts)..." -ForegroundColor Yellow
$commentCount = 0
foreach ($postId in $postIds) {
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
Write-Host "Created $commentCount comments" -ForegroundColor Green
Write-Host ""

