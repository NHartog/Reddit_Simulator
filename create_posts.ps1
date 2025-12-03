$baseUrl = "http://localhost:8080"
$postsPerSubreddit = 50

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
    Write-Host "ERROR: No subreddits found. Please run create_subreddits.ps1 first." -ForegroundColor Red
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
    Write-Host "ERROR: No users found. Please run create_users.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

Write-Host "Creating posts ($postsPerSubreddit per subreddit)..." -ForegroundColor Yellow
$postIds = @()
$postCount = 0
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
Write-Host "Created $postCount posts" -ForegroundColor Green
Write-Host ""

