# Testing the Reddit Simulator REST API

## Method 1: Using PowerShell (Windows)

### Step 1: Start the Server
```powershell
cd C:\Users\nicho\web-projects\reddit-simulator-gleam
gleam run -m reddit_simulator_gleam/rest_api_main
```

Keep this terminal open and running.

### Step 2: Test with PowerShell Commands

Open a **new** PowerShell window and run:

```powershell
# Register a user
$body = @{
    username = "testuser"
    email = "test@example.com"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/users" -Method Post -Body $body -ContentType "application/json"

# Get a user (replace USER_ID with the ID from above)
Invoke-RestMethod -Uri "http://localhost:8080/users/USER_ID" -Method Get

# Create a subreddit
$body = @{
    name = "test"
    description = "Test subreddit"
    creatorId = "USER_ID"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8080/subreddits" -Method Post -Body $body -ContentType "application/json"
```

## Method 2: Using the CLI Client

### Step 1: Start the Server (Terminal 1)
```powershell
cd C:\Users\nicho\web-projects\reddit-simulator-gleam
gleam run -m reddit_simulator_gleam/rest_api_main
```

### Step 2: Run the Client (Terminal 2)
```powershell
cd C:\Users\nicho\web-projects\reddit-simulator-gleam
gleam run -m reddit_simulator_gleam/cli_client
```

## Method 3: Using curl.exe (if installed)

If you have actual curl.exe installed (not the PowerShell alias), you can use:

```powershell
curl.exe -X POST http://localhost:8080/users -H "Content-Type: application/json" -d "{\"username\":\"testuser\",\"email\":\"test@example.com\"}"
```

## Troubleshooting

- **"Connection refused"**: Make sure the server is running in Terminal 1
- **"Port already in use"**: Another process is using port 8080
- **PowerShell curl error**: Use `Invoke-RestMethod` instead (see Method 1)

