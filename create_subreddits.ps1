$baseUrl = "http://localhost:8080"
$numSubreddits = 100

Write-Host "Getting existing users..." -ForegroundColor Yellow
$userIds = @()
try {
    # Get users by trying to fetch them (we'll use user_1 through user_10000)
    for ($i = 1; $i -le 10000; $i++) {
        try {
            $user = Invoke-RestMethod -Uri "$baseUrl/users/user_$i" -Method Get -ErrorAction Stop 2>&1 | Out-Null
            $user = Invoke-RestMethod -Uri "$baseUrl/users/user_$i" -Method Get -ErrorAction Stop
            if ($user.id) {
                $userIds += $user.id
            }
        } catch {
            # User doesn't exist, skip
        }
        if ($i % 1000 -eq 0 -and $userIds.Count -gt 0) {
            break
        }
    }
} catch {
    Write-Host "Error getting users: $_" -ForegroundColor Red
}

if ($userIds.Count -eq 0) {
    Write-Host "ERROR: No users found. Please run create_users.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

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
Write-Host "Created $($subredditIds.Count) subreddits" -ForegroundColor Green
Write-Host ""

