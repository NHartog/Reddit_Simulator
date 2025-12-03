$baseUrl = "http://localhost:8080"
$numVotes = 2000
$maxPosts = 1000

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
    Write-Host "ERROR: No users found. Please run create_users.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

Write-Host "Creating $numVotes votes..." -ForegroundColor Yellow
$voteCount = 0
for ($i = 1; $i -le $numVotes; $i++) {
    try {
        $userId = $userIds[(Get-Random -Minimum 0 -Maximum $userIds.Count)]
        $postIdx = Get-Random -Minimum 0 -Maximum $postIds.Count
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
Write-Host "Created $voteCount votes" -ForegroundColor Green
Write-Host ""

