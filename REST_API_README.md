# Reddit Simulator REST API

This document describes the REST API implementation for the Reddit Simulator project.

## Overview

The REST API provides HTTP endpoints for all fully implemented features of the Reddit Simulator engine. The API follows a structure similar to Reddit's official API and uses JSON for request/response bodies.

## Architecture

The REST API consists of:
- **HTTP Server** (`http_server_ffi.erl`): Erlang HTTP server using `gen_tcp`
- **HTTP Bridge Actor** (`http_bridge_actor.gleam`): Converts Erlang messages to Gleam actor messages
- **REST API Handler** (`rest_api_handler.gleam`): Routes HTTP requests and handles all endpoints
- **JSON Encoder/Decoder** (`json_encoder.gleam`, `json_decoder.gleam`): Handles JSON serialization
- **CLI Client** (`cli_client.gleam`): Command-line client for testing the API

## Running the Server

To start the REST API server:

```bash
gleam run -m reddit_simulator_gleam/rest_api_main
```

The server will start on `http://localhost:8080`

## Running the CLI Client

To run the command-line client demo:

```bash
gleam run -m reddit_simulator_gleam/cli_client
```

**Note:** The server must be running for the client to work.

## API Endpoints

### User Management

#### Register User
- **POST** `/users`
- **Request Body:**
  ```json
  {
    "username": "alice",
    "email": "alice@example.com"
  }
  ```
- **Response:** `201 Created`
  ```json
  {
    "id": "user_1"
  }
  ```

#### Get User
- **GET** `/users/{userId}`
- **Response:** `200 OK`
  ```json
  {
    "id": "user_1"
  }
  ```

### Subreddit Management

#### Create Subreddit
- **POST** `/subreddits`
- **Request Body:**
  ```json
  {
    "name": "programming",
    "description": "Discussion about programming",
    "creatorId": "user_1"
  }
  ```
- **Response:** `201 Created` (subreddit object)

#### Get Subreddit
- **GET** `/subreddits/{subredditId}`
- **Response:** `200 OK` (subreddit object)

#### Get Subreddit With Members
- **GET** `/subreddits/{subredditId}/members`
- **Response:** `200 OK` (subreddit with member list)

#### Subscribe to Subreddit
- **POST** `/subreddits/{subredditId}/subscribe`
- **Request Body:**
  ```json
  {
    "userId": "user_1"
  }
  ```
- **Response:** `200 OK` with `{"success":true}`

#### Unsubscribe from Subreddit
- **POST** `/subreddits/{subredditId}/unsubscribe`
- **Request Body:**
  ```json
  {
    "userId": "user_1"
  }
  ```
- **Response:** `200 OK` with `{"success":true}`

### Post Management

#### Create Post
- **POST** `/posts`
- **Request Body:**
  ```json
  {
    "title": "Hello World",
    "content": "This is my first post!",
    "subredditId": "programming",
    "authorId": "user_1"
  }
  ```
- **Response:** `201 Created` (post object)

#### Get Post
- **GET** `/posts/{postId}`
- **Response:** `200 OK` (post object with upvotes/downvotes)

#### Get Subreddit Posts
- **GET** `/subreddits/{subredditId}/posts`
- **Response:** `200 OK` (array of post objects, limited to 25)

### Voting

#### Vote on Post
- **POST** `/posts/{postId}/vote`
- **Request Body:**
  ```json
  {
    "userId": "user_1",
    "voteType": "upvote"
  }
  ```
- **voteType:** `"upvote"` or `"downvote"`
- **Response:** `200 OK` with `{"success":true}`

### Comment Management

#### Create Comment
- **POST** `/comments`
- **Request Body:**
  ```json
  {
    "content": "Great post!",
    "subredditId": "programming",
    "authorId": "user_1",
    "parentCommentId": null
  }
  ```
- **parentCommentId:** Optional. If provided, creates a nested comment
- **Response:** `201 Created` (comment object)

#### Get Comment
- **GET** `/comments/{commentId}`
- **Response:** `200 OK` (comment object)

#### Get Subreddit Comments
- **GET** `/subreddits/{subredditId}/comments`
- **Response:** `200 OK` (comment tree with hierarchical structure)

### Feed

#### Get Feed
- **GET** `/feed`
- **Response:** `200 OK` (array of feed objects, limited to 25)

### Direct Messages

#### Send Direct Message
- **POST** `/messages`
- **Request Body:**
  ```json
  {
    "senderId": "user_1",
    "recipientId": "user_2",
    "content": "Hello!"
  }
  ```
- **Response:** `201 Created` (direct message object)

#### Get Direct Messages
- **GET** `/users/{userId}/messages`
- **Response:** `200 OK` (array of direct message objects)

## Error Responses

All errors return JSON in the following format:

```json
{
  "error": "Error message here"
}
```

Common HTTP status codes:
- `200 OK` - Success
- `201 Created` - Resource created successfully
- `400 Bad Request` - Invalid request data
- `404 Not Found` - Resource not found
- `405 Method Not Allowed` - HTTP method not supported
- `500 Internal Server Error` - Server error

## Example Usage with curl

```bash
# Register a user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com"}'

# Create a subreddit
curl -X POST http://localhost:8080/subreddits \
  -H "Content-Type: application/json" \
  -d '{"name":"programming","description":"Programming discussions","creatorId":"user_1"}'

# Create a post
curl -X POST http://localhost:8080/posts \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello","content":"World","subredditId":"programming","authorId":"user_1"}'

# Get a post
curl http://localhost:8080/posts/post_1

# Vote on a post
curl -X POST http://localhost:8080/posts/post_1/vote \
  -H "Content-Type: application/json" \
  -d '{"userId":"user_1","voteType":"upvote"}'
```

## Implementation Notes

- The HTTP server uses Erlang's `gen_tcp` for simplicity (no external dependencies)
- All communication between HTTP server and Gleam actors goes through a bridge actor
- JSON encoding/decoding is implemented manually (basic implementation)
- The API follows RESTful conventions similar to Reddit's API structure
- All endpoints return JSON with appropriate HTTP status codes

