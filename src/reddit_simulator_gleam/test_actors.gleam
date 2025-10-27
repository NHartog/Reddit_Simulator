import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import reddit_simulator_gleam/all_types.{
  type MasterEngineMessage, CreateSubreddit, GetSubreddit,
  GetSubredditWithMembers, GetUser, ProcessRequest, RegisterUser,
  SubscribeToSubreddit, UnsubscribeFromSubreddit,
}
import reddit_simulator_gleam/master_engine_actor.{create_master_engine_actor}

pub fn test_master_engine_actor() {
  io.println("=== Testing User Actor Functionality ===")

  // Create the master engine actor
  case create_master_engine_actor() {
    Ok(engine_subject) -> {
      io.println("✓ MasterEngineActor created successfully")

      // Test user-related functionality
      test_register_users(engine_subject)
      test_get_users(engine_subject)
      test_string_routing_users(engine_subject)

      // Test subreddit functionality
      test_subreddit_functionality(engine_subject)

      io.println("=== All tests completed successfully! ===")
    }
    Error(msg) -> {
      io.println("✗ Failed to create MasterEngineActor: " <> msg)
    }
  }
}

fn test_register_users(engine_subject: process.Subject(MasterEngineMessage)) {
  io.println("\n--- Testing User Registration ---")

  let users = [
    #("alice", "alice@example.com"),
    #("bob", "bob@example.com"),
    #("charlie", "charlie@example.com"),
    #("diana", "diana@example.com"),
    #("eve", "eve@example.com"),
  ]

  list.fold(users, 1, fn(acc, user_data) {
    let #(username, email) = user_data
    let reply = process.new_subject()
    let message = RegisterUser(reply, username, email)

    let _ = process.send(engine_subject, message)

    case process.receive(reply, 1000) {
      Ok(response) -> {
        io.println("🔍 CLIENT RECEIVED MESSAGE: " <> response)
        io.println(
          "✓ User " <> int.to_string(acc) <> " registered: " <> response,
        )
        acc + 1
      }
      Error(_) -> {
        io.println("✗ User " <> int.to_string(acc) <> " registration timeout")
        acc + 1
      }
    }
  })
}

fn test_get_users(engine_subject: process.Subject(MasterEngineMessage)) {
  io.println("\n--- Testing User Retrieval ---")

  let user_ids = ["user_1", "user_2", "user_3", "user_4", "user_5"]

  list.fold(user_ids, 1, fn(acc, user_id) {
    let reply = process.new_subject()
    let message = GetUser(reply, user_id)

    let _ = process.send(engine_subject, message)

    case process.receive(reply, 1000) {
      Ok(response) -> {
        io.println("🔍 CLIENT RECEIVED MESSAGE: " <> response)
        io.println(
          "✓ User " <> int.to_string(acc) <> " retrieved: " <> response,
        )
        acc + 1
      }
      Error(_) -> {
        io.println("✗ User " <> int.to_string(acc) <> " retrieval timeout")
        acc + 1
      }
    }
  })
}

fn test_string_routing_users(
  engine_subject: process.Subject(MasterEngineMessage),
) {
  io.println("\n--- Testing String-Based User Request Routing ---")

  let requests = [
    #("create_user", "username:alice,email:alice@example.com"),
    #("get_user", "user_id:user_1"),
    #("create_user", "username:bob,email:bob@example.com"),
    #("get_user", "user_id:user_2"),
    #("unknown_request", "some:data"),
  ]

  list.fold(requests, 1, fn(acc, request_data) {
    let #(request_type, request_data) = request_data
    let reply = process.new_subject()
    let message = ProcessRequest(reply, request_type, request_data)

    let _ = process.send(engine_subject, message)

    case process.receive(reply, 1000) {
      Ok(Ok(response)) -> {
        io.println("🔍 CLIENT RECEIVED MESSAGE: " <> response)
        io.println(
          "✓ Request "
          <> int.to_string(acc)
          <> " ("
          <> request_type
          <> "): "
          <> response,
        )
        acc + 1
      }
      Ok(Error(msg)) -> {
        io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
        io.println(
          "✗ Request "
          <> int.to_string(acc)
          <> " ("
          <> request_type
          <> ") failed: "
          <> msg,
        )
        acc + 1
      }
      Error(_) -> {
        io.println(
          "✗ Request "
          <> int.to_string(acc)
          <> " ("
          <> request_type
          <> ") timeout",
        )
        acc + 1
      }
    }
  })
}

fn test_subreddit_functionality(
  engine_subject: process.Subject(MasterEngineMessage),
) {
  io.println("\n=== Testing Subreddit Functionality ===")

  // Step 1: Create 5 users
  io.println("\n--- Step 1: Creating 5 users ---")
  let users = [
    #("alice", "alice@example.com"),
    #("bob", "bob@example.com"),
    #("charlie", "charlie@example.com"),
    #("diana", "diana@example.com"),
    #("eve", "eve@example.com"),
  ]

  let user_data =
    list.fold(users, #([], []), fn(acc, user_info) {
      let #(user_ids, user_id_to_name) = acc
      let #(username, email) = user_info
      let reply = process.new_subject()
      let message = RegisterUser(reply, username, email)

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(response) -> {
          io.println("🔍 CLIENT RECEIVED: " <> response)
          io.println("✓ User '" <> username <> "' registered: " <> response)
          #(
            list.append(user_ids, [response]),
            list.append(user_id_to_name, [#(response, username)]),
          )
        }
        Error(_) -> {
          io.println("✗ User '" <> username <> "' registration timeout")
          acc
        }
      }
    })

  let user_ids = user_data.0
  let user_id_to_name = user_data.1

  // Step 2: User 4 (diana) creates a subreddit
  io.println("\n--- Step 2: User 4 (diana) creates a subreddit ---")
  case get_user_by_index(user_ids, 3) {
    None -> {
      io.println("✗ User 4 not found, cannot create subreddit")
    }
    Some(creator_id) -> {
      let reply = process.new_subject()
      let message =
        CreateSubreddit(
          reply,
          "programming",
          "A place to discuss programming",
          creator_id,
        )

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(subreddit)) -> {
          io.println("🔍 CLIENT RECEIVED: Subreddit created successfully")
          io.println("✓ Subreddit 'programming' created by " <> creator_id)
          io.println("  - ID: " <> subreddit.id)
          io.println("  - Name: " <> subreddit.name)
          io.println("  - Description: " <> subreddit.description)
          io.println(
            "  - Subscriber count: "
            <> int.to_string(subreddit.subscriber_count),
          )

          // Step 3: Users 1, 2, and 5 join the subreddit
          test_users_join_subreddit(
            engine_subject,
            subreddit.id,
            user_ids,
            user_id_to_name,
          )
        }
        Ok(Error(msg)) -> {
          io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
          io.println("✗ Failed to create subreddit: " <> msg)
        }
        Error(_) -> {
          io.println("✗ Subreddit creation timeout")
        }
      }
    }
  }
}

fn test_users_join_subreddit(
  engine_subject: process.Subject(MasterEngineMessage),
  subreddit_id: String,
  user_ids: List(String),
  user_id_to_name: List(#(String, String)),
) {
  io.println("\n--- Step 3: Users 1, 2, and 5 join the subreddit ---")

  // User 1 (alice) joins
  case get_user_by_index(user_ids, 0) {
    None -> {
      io.println("✗ User 1 not found, cannot join subreddit")
    }
    Some(user1_id) -> {
      let username1 = get_username_by_id(user_id_to_name, user1_id)
      let reply = process.new_subject()
      let message = SubscribeToSubreddit(reply, user1_id, subreddit_id)

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> {
          io.println(
            "🔍 CLIENT RECEIVED: " <> username1 <> " joined successfully",
          )
          io.println(
            "✓ " <> username1 <> " (" <> user1_id <> ") joined subreddit",
          )
        }
        Ok(Error(msg)) -> {
          io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
          io.println("✗ " <> username1 <> " failed to join: " <> msg)
        }
        Error(_) -> {
          io.println("✗ " <> username1 <> " join timeout")
        }
      }
    }
  }

  // User 2 (bob) joins
  case get_user_by_index(user_ids, 1) {
    None -> {
      io.println("✗ User 2 not found, cannot join subreddit")
    }
    Some(user2_id) -> {
      let username2 = get_username_by_id(user_id_to_name, user2_id)
      let reply = process.new_subject()
      let message = SubscribeToSubreddit(reply, user2_id, subreddit_id)

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> {
          io.println(
            "🔍 CLIENT RECEIVED: " <> username2 <> " joined successfully",
          )
          io.println(
            "✓ " <> username2 <> " (" <> user2_id <> ") joined subreddit",
          )
        }
        Ok(Error(msg)) -> {
          io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
          io.println("✗ " <> username2 <> " failed to join: " <> msg)
        }
        Error(_) -> {
          io.println("✗ " <> username2 <> " join timeout")
        }
      }
    }
  }

  // User 5 (eve) joins
  case get_user_by_index(user_ids, 4) {
    None -> {
      io.println("✗ User 5 not found, cannot join subreddit")
    }
    Some(user5_id) -> {
      let username5 = get_username_by_id(user_id_to_name, user5_id)
      let reply = process.new_subject()
      let message = SubscribeToSubreddit(reply, user5_id, subreddit_id)

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(_)) -> {
          io.println(
            "🔍 CLIENT RECEIVED: " <> username5 <> " joined successfully",
          )
          io.println(
            "✓ " <> username5 <> " (" <> user5_id <> ") joined subreddit",
          )
        }
        Ok(Error(msg)) -> {
          io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
          io.println("✗ " <> username5 <> " failed to join: " <> msg)
        }
        Error(_) -> {
          io.println("✗ " <> username5 <> " join timeout")
        }
      }
    }
  }

  // Step 4: Verify the subreddit state
  io.println("\n--- Step 4: Verifying subreddit state ---")
  let reply = process.new_subject()
  let message = GetSubredditWithMembers(reply, subreddit_id)

  let _ = process.send(engine_subject, message)

  case process.receive(reply, 1000) {
    Ok(Ok(subreddit_with_members)) -> {
      io.println(
        "🔍 CLIENT RECEIVED: Subreddit with members retrieved successfully",
      )
      let subreddit = subreddit_with_members.subreddit
      let member_ids = subreddit_with_members.member_ids
      io.println("✓ Final subreddit state:")
      io.println("  - ID: " <> subreddit.id)
      io.println("  - Name: " <> subreddit.name)
      io.println("  - Description: " <> subreddit.description)
      io.println(
        "  - Subscriber count: " <> int.to_string(subreddit.subscriber_count),
      )
      io.println(
        "  - Moderator IDs: "
        <> list.length(subreddit.moderator_ids) |> int.to_string,
      )
      io.println("  - Member IDs: [" <> string.join(member_ids, ", ") <> "]")
      io.println(
        "  - Total members: " <> int.to_string(list.length(member_ids)),
      )
    }
    Ok(Error(msg)) -> {
      io.println("🔍 CLIENT RECEIVED ERROR: " <> msg)
      io.println("✗ Failed to retrieve subreddit: " <> msg)
    }
    Error(_) -> {
      io.println("✗ Subreddit retrieval timeout")
    }
  }
}

fn get_user_by_index(user_ids: List(String), index: Int) -> Option(String) {
  case list.drop(user_ids, index) {
    [] -> None
    [user_id, ..] -> Some(user_id)
  }
}

fn get_username_by_id(
  user_id_to_name: List(#(String, String)),
  user_id: String,
) -> String {
  case
    list.find(user_id_to_name, fn(pair) {
      let #(id, _) = pair
      id == user_id
    })
  {
    Ok(#(_, username)) -> username
    Error(_) -> "Unknown User"
  }
}
