$baseUrl = "http://localhost:8080"
$numUsers = 10000

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
Write-Host "Created $($userIds.Count) users" -ForegroundColor Green
Write-Host ""

