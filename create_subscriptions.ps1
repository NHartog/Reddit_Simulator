$baseUrl = "http://localhost:8080"
$numSubscriptions = 5000

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

Write-Host "Creating $numSubscriptions subscriptions..." -ForegroundColor Yellow
$subscriptionCount = 0
for ($i = 1; $i -le $numSubscriptions; $i++) {
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
Write-Host "Created $subscriptionCount subscriptions" -ForegroundColor Green
Write-Host ""

