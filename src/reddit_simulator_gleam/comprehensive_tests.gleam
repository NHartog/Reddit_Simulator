import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import reddit_simulator_gleam/engine_types.{
  type MasterEngineMessage, CreateComment, CreatePost, CreateSubreddit, GetFeed,
  GetPost, GetSubredditComments, GetSubredditWithMembers, GetUser, RegisterUser,
  SubscribeToSubreddit, VoteOnPost,
}
import reddit_simulator_gleam/master_engine_actor.{create_master_engine_actor}
import reddit_simulator_gleam/simulation_types.{
  type Comment, type CommentTree, type FeedObject, type VoteType, Downvote,
  Upvote,
}

// =============================================================================
// COMPREHENSIVE TEST SUITE
// =============================================================================
// This file contains all tests for the Reddit Simulator system, organized by functionality

pub fn run_all_tests() {
  io.println("=== Reddit Simulator Comprehensive Test Suite ===")
  io.println("")

  // Create the master engine actor
  case create_master_engine_actor() {
    Ok(engine_subject) -> {
      io.println("✓ MasterEngineActor created successfully")
      io.println("")

      // Run all test suites
      let user_data = test_user_management(engine_subject)
      let subreddit_data = test_subreddit_management(engine_subject, user_data)
      let post_data =
        test_post_management(engine_subject, user_data, subreddit_data)
      test_comment_management(engine_subject, user_data, subreddit_data)
      test_upvote_functionality(engine_subject, user_data, post_data.post_id)
      test_feed_functionality(engine_subject, user_data, subreddit_data)

      io.println("")
      io.println("=== All tests completed successfully! ===")
    }
    Error(msg) -> {
      io.println("✗ Failed to create MasterEngineActor: " <> msg)
    }
  }
}

// =============================================================================
// USER MANAGEMENT TESTS
// =============================================================================

type UserTestData {
  UserTestData(user_ids: List(String), user_id_to_name: List(#(String, String)))
}

fn test_user_management(
  engine_subject: process.Subject(MasterEngineMessage),
) -> UserTestData {
  io.println("--- Testing User Management ---")

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
          io.println("✓ User '" <> username <> "' registered: " <> response)
          // Extract just the user ID part (after the colon)
          let user_id = case string.split(response, ":") {
            [_, id] -> id
            _ -> response
            // fallback to full response if no colon found
          }
          #(
            list.append(user_ids, [user_id]),
            list.append(user_id_to_name, [#(user_id, username)]),
          )
        }
        Error(_) -> {
          io.println("✗ User '" <> username <> "' registration timeout")
          acc
        }
      }
    })

  // Test user retrieval
  list.fold(user_data.0, 1, fn(acc, user_id) {
    let reply = process.new_subject()
    let message = GetUser(reply, user_id)

    let _ = process.send(engine_subject, message)

    case process.receive(reply, 1000) {
      Ok(response) -> {
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

  UserTestData(user_ids: user_data.0, user_id_to_name: user_data.1)
}

// =============================================================================
// SUBREDDIT MANAGEMENT TESTS
// =============================================================================

type SubredditTestData {
  SubredditTestData(subreddit_id: String)
}

fn test_subreddit_management(
  engine_subject: process.Subject(MasterEngineMessage),
  user_data: UserTestData,
) -> SubredditTestData {
  io.println("")
  io.println("--- Testing Subreddit Management ---")

  // Create a subreddit with user 4 (diana)
  case get_user_by_index(user_data.user_ids, 3) {
    None -> {
      io.println("✗ User 4 not found, cannot create subreddit")
      SubredditTestData(subreddit_id: "")
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
          io.println("✓ Subreddit 'programming' created by " <> creator_id)
          io.println("  - ID: " <> subreddit.id)
          io.println("  - Name: " <> subreddit.name)
          io.println("  - Description: " <> subreddit.description)
          io.println(
            "  - Subscriber count: "
            <> int.to_string(subreddit.subscriber_count),
          )

          // Test users joining the subreddit
          test_users_join_subreddit(engine_subject, subreddit.id, user_data)

          SubredditTestData(subreddit_id: subreddit.id)
        }
        Ok(Error(msg)) -> {
          io.println("✗ Failed to create subreddit: " <> msg)
          SubredditTestData(subreddit_id: "")
        }
        Error(_) -> {
          io.println("✗ Subreddit creation timeout")
          SubredditTestData(subreddit_id: "")
        }
      }
    }
  }
}

fn test_users_join_subreddit(
  engine_subject: process.Subject(MasterEngineMessage),
  subreddit_id: String,
  user_data: UserTestData,
) {
  // Users 1, 2, and 5 join the subreddit
  let join_users = [0, 1, 4]
  // alice, bob, eve

  list.each(join_users, fn(user_index) {
    case get_user_by_index(user_data.user_ids, user_index) {
      None -> {
        io.println("✗ User " <> int.to_string(user_index + 1) <> " not found")
      }
      Some(user_id) -> {
        let username = get_username_by_id(user_data.user_id_to_name, user_id)
        let reply = process.new_subject()
        let message = SubscribeToSubreddit(reply, user_id, subreddit_id)

        let _ = process.send(engine_subject, message)

        case process.receive(reply, 1000) {
          Ok(Ok(_)) -> {
            io.println(
              "✓ " <> username <> " (" <> user_id <> ") joined subreddit",
            )
          }
          Ok(Error(msg)) -> {
            io.println("✗ " <> username <> " failed to join: " <> msg)
          }
          Error(_) -> {
            io.println("✗ " <> username <> " join timeout")
          }
        }
      }
    }
  })

  // Verify final subreddit state
  let reply = process.new_subject()
  let message = GetSubredditWithMembers(reply, subreddit_id)

  let _ = process.send(engine_subject, message)

  case process.receive(reply, 1000) {
    Ok(Ok(subreddit_with_members)) -> {
      let subreddit = subreddit_with_members.subreddit
      let member_ids = subreddit_with_members.member_ids
      io.println("✓ Final subreddit state:")
      io.println(
        "  - Subscriber count: " <> int.to_string(subreddit.subscriber_count),
      )
      io.println(
        "  - Total members: " <> int.to_string(list.length(member_ids)),
      )
    }
    Ok(Error(msg)) -> {
      io.println("✗ Failed to retrieve subreddit: " <> msg)
    }
    Error(_) -> {
      io.println("✗ Subreddit retrieval timeout")
    }
  }
}

// =============================================================================
// POST MANAGEMENT TESTS
// =============================================================================

type PostTestData {
  PostTestData(post_id: String)
}

fn test_post_management(
  engine_subject: process.Subject(MasterEngineMessage),
  user_data: UserTestData,
  subreddit_data: SubredditTestData,
) -> PostTestData {
  io.println("")
  io.println("--- Testing Post Management ---")

  // Use user 4 (diana) to create a post
  case get_user_by_index(user_data.user_ids, 3) {
    None -> {
      io.println("✗ User 4 not found, cannot create post")
      PostTestData(post_id: "")
    }
    Some(author_id) -> {
      let reply = process.new_subject()
      let message =
        CreatePost(
          reply,
          "Test Post",
          "This is a test post content",
          author_id,
          subreddit_data.subreddit_id,
        )

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(post)) -> {
          io.println("✓ Post created successfully!")
          io.println("  Title: " <> post.title)
          io.println("  Content: " <> post.content)
          io.println(
            "  Author: "
            <> get_username_by_id(user_data.user_id_to_name, post.author_id),
          )

          // Post created successfully, no need to retrieve it for this test

          PostTestData(post_id: post.id)
        }
        Ok(Error(msg)) -> {
          io.println("✗ Failed to create post: " <> msg)
          PostTestData(post_id: "")
        }
        Error(_) -> {
          io.println("✗ Post creation timeout")
          PostTestData(post_id: "")
        }
      }
    }
  }
}

// =============================================================================
// UPVOTE FUNCTIONALITY TESTS
// =============================================================================

fn test_upvote_functionality(
  engine_subject: process.Subject(MasterEngineMessage),
  user_data: UserTestData,
  post_id: String,
) {
  io.println("")
  io.println("--- Testing Upvote Functionality ---")

  // Test upvoting by 3 users
  io.println("👍 Testing upvotes by 3 users...")

  // User 1 upvotes
  case get_user_by_index(user_data.user_ids, 0) {
    None -> {
      io.println("✗ User 1 not found, cannot test upvote")
    }
    Some(user1_id) -> {
      let upvote1_reply = process.new_subject()
      let upvote1_message = VoteOnPost(upvote1_reply, user1_id, post_id, Upvote)

      let _ = process.send(engine_subject, upvote1_message)

      case process.receive(upvote1_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ User " <> user1_id <> " upvoted successfully")
        }
        Ok(Error(msg)) -> {
          io.println("✗ User " <> user1_id <> " upvote failed: " <> msg)
        }
        Error(_) -> {
          io.println("✗ User " <> user1_id <> " upvote timeout")
        }
      }
    }
  }

  // User 2 upvotes
  case get_user_by_index(user_data.user_ids, 1) {
    None -> {
      io.println("✗ User 2 not found, cannot test upvote")
    }
    Some(user2_id) -> {
      let upvote2_reply = process.new_subject()
      let upvote2_message = VoteOnPost(upvote2_reply, user2_id, post_id, Upvote)

      let _ = process.send(engine_subject, upvote2_message)

      case process.receive(upvote2_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ User " <> user2_id <> " upvoted successfully")
        }
        Ok(Error(msg)) -> {
          io.println("✗ User " <> user2_id <> " upvote failed: " <> msg)
        }
        Error(_) -> {
          io.println("✗ User " <> user2_id <> " upvote timeout")
        }
      }
    }
  }

  // User 3 upvotes
  case get_user_by_index(user_data.user_ids, 2) {
    None -> {
      io.println("✗ User 3 not found, cannot test upvote")
    }
    Some(user3_id) -> {
      let upvote3_reply = process.new_subject()
      let upvote3_message = VoteOnPost(upvote3_reply, user3_id, post_id, Upvote)

      let _ = process.send(engine_subject, upvote3_message)

      case process.receive(upvote3_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ User " <> user3_id <> " upvoted successfully")
        }
        Ok(Error(msg)) -> {
          io.println("✗ User " <> user3_id <> " upvote failed: " <> msg)
        }
        Error(_) -> {
          io.println("✗ User " <> user3_id <> " upvote timeout")
        }
      }
    }
  }

  // User 4 downvotes
  io.println("👎 Testing downvote by 1 user...")
  case get_user_by_index(user_data.user_ids, 3) {
    None -> {
      io.println("✗ User 4 not found, cannot test downvote")
    }
    Some(user4_id) -> {
      let downvote_reply = process.new_subject()
      let downvote_message =
        VoteOnPost(downvote_reply, user4_id, post_id, Downvote)

      let _ = process.send(engine_subject, downvote_message)

      case process.receive(downvote_reply, 1000) {
        Ok(Ok(_)) -> {
          io.println("✓ User " <> user4_id <> " downvoted successfully")
        }
        Ok(Error(msg)) -> {
          io.println("✗ User " <> user4_id <> " downvote failed: " <> msg)
        }
        Error(_) -> {
          io.println("✗ User " <> user4_id <> " downvote timeout")
        }
      }
    }
  }

  // Get final post details with upvote/downvote counts and karma
  io.println("")
  io.println("📊 Final Post Details:")
  let post_reply = process.new_subject()
  let post_message = GetPost(post_reply, post_id)

  let _ = process.send(engine_subject, post_message)

  case process.receive(post_reply, 1000) {
    Ok(Ok(post)) -> {
      let karma = post.upvotes - post.downvotes
      io.println("  Title: " <> post.title)
      io.println("  Content: " <> post.content)
      io.println(
        "  Author: "
        <> get_username_by_id(user_data.user_id_to_name, post.author_id),
      )
      io.println("  Upvotes: " <> int.to_string(post.upvotes))
      io.println("  Downvotes: " <> int.to_string(post.downvotes))
      io.println("  Karma: " <> int.to_string(karma))
    }
    Ok(Error(msg)) -> {
      io.println("✗ Failed to retrieve post details: " <> msg)
    }
    Error(_) -> {
      io.println("✗ Post retrieval timeout")
    }
  }

  io.println("✓ Upvote functionality test completed!")
}

// =============================================================================
// COMMENT MANAGEMENT TESTS
// =============================================================================

fn test_comment_management(
  engine_subject: process.Subject(MasterEngineMessage),
  user_data: UserTestData,
  subreddit_data: SubredditTestData,
) {
  io.println("")
  io.println("--- Testing Comment Management (Hierarchical) ---")

  // Test hierarchical comment structure:
  // User1 -> User2 -> User3
  //        -> User4 (replying to User2)

  case get_user_by_index(user_data.user_ids, 0) {
    None -> {
      io.println("✗ User 1 not found, cannot test comments")
    }
    Some(user1_id) -> {
      // User1 creates the first comment (root comment)
      let comment1_reply = process.new_subject()
      let comment1_message =
        CreateComment(
          comment1_reply,
          "This is the first comment in the subreddit!",
          user1_id,
          subreddit_data.subreddit_id,
          None,
        )

      let _ = process.send(engine_subject, comment1_message)

      case process.receive(comment1_reply, 1000) {
        Ok(Ok(comment1)) -> {
          io.println("✓ User1 created root comment: " <> comment1.id)
          io.println("  Content: " <> comment1.content)
          io.println("  Depth: " <> int.to_string(comment1.depth))

          // User2 replies to User1's comment
          case get_user_by_index(user_data.user_ids, 1) {
            None -> {
              io.println("✗ User 2 not found")
            }
            Some(user2_id) -> {
              let comment2_reply = process.new_subject()
              let comment2_message =
                CreateComment(
                  comment2_reply,
                  "Great point! I agree with this.",
                  user2_id,
                  subreddit_data.subreddit_id,
                  Some(comment1.id),
                )

              let _ = process.send(engine_subject, comment2_message)

              case process.receive(comment2_reply, 1000) {
                Ok(Ok(comment2)) -> {
                  io.println("✓ User2 replied to User1: " <> comment2.id)
                  io.println("  Content: " <> comment2.content)
                  io.println("  Depth: " <> int.to_string(comment2.depth))

                  // User3 replies to User2's comment
                  case get_user_by_index(user_data.user_ids, 2) {
                    None -> {
                      io.println("✗ User 3 not found")
                    }
                    Some(user3_id) -> {
                      let comment3_reply = process.new_subject()
                      let comment3_message =
                        CreateComment(
                          comment3_reply,
                          "I have a different perspective on this...",
                          user3_id,
                          subreddit_data.subreddit_id,
                          Some(comment2.id),
                        )

                      let _ = process.send(engine_subject, comment3_message)

                      case process.receive(comment3_reply, 1000) {
                        Ok(Ok(comment3)) -> {
                          io.println(
                            "✓ User3 replied to User2: " <> comment3.id,
                          )
                          io.println("  Content: " <> comment3.content)
                          io.println(
                            "  Depth: " <> int.to_string(comment3.depth),
                          )

                          // User4 replies to User2's comment (sibling to User3)
                          case get_user_by_index(user_data.user_ids, 4) {
                            None -> {
                              io.println("✗ User 4 not found")
                            }
                            Some(user4_id) -> {
                              let comment4_reply = process.new_subject()
                              let comment4_message =
                                CreateComment(
                                  comment4_reply,
                                  "Actually, I think User2 is right about this.",
                                  user4_id,
                                  subreddit_data.subreddit_id,
                                  Some(comment2.id),
                                )

                              let _ =
                                process.send(engine_subject, comment4_message)

                              case process.receive(comment4_reply, 1000) {
                                Ok(Ok(comment4)) -> {
                                  io.println(
                                    "✓ User4 replied to User2: " <> comment4.id,
                                  )
                                  io.println("  Content: " <> comment4.content)
                                  io.println(
                                    "  Depth: " <> int.to_string(comment4.depth),
                                  )

                                  // Display the hierarchical structure
                                  display_comment_hierarchy(
                                    engine_subject,
                                    subreddit_data.subreddit_id,
                                    user_data,
                                  )
                                }
                                Ok(Error(msg)) -> {
                                  io.println(
                                    "✗ User4 comment creation failed: " <> msg,
                                  )
                                }
                                Error(_) -> {
                                  io.println("✗ User4 comment creation timeout")
                                }
                              }
                            }
                          }
                        }
                        Ok(Error(msg)) -> {
                          io.println("✗ User3 comment creation failed: " <> msg)
                        }
                        Error(_) -> {
                          io.println("✗ User3 comment creation timeout")
                        }
                      }
                    }
                  }
                }
                Ok(Error(msg)) -> {
                  io.println("✗ User2 comment creation failed: " <> msg)
                }
                Error(_) -> {
                  io.println("✗ User2 comment creation timeout")
                }
              }
            }
          }
        }
        Ok(Error(msg)) -> {
          io.println("✗ User1 comment creation failed: " <> msg)
        }
        Error(_) -> {
          io.println("✗ User1 comment creation timeout")
        }
      }
    }
  }
}

fn display_comment_hierarchy(
  engine_subject: process.Subject(MasterEngineMessage),
  subreddit_id: String,
  user_data: UserTestData,
) {
  io.println("")
  io.println("--- Comment Hierarchy Visualization ---")

  let reply = process.new_subject()
  let message = GetSubredditComments(reply, subreddit_id)

  let _ = process.send(engine_subject, message)

  case process.receive(reply, 1000) {
    Ok(Ok(comment_tree)) -> {
      io.println(
        "✓ Retrieved comment tree with "
        <> int.to_string(dict.size(comment_tree.comments))
        <> " comments",
      )
      io.println("")
      io.println("Comment Hierarchy:")
      io.println("==================")

      // Display root comments and their replies
      list.each(comment_tree.root_comments, fn(root_comment_id) {
        case dict.get(comment_tree.comments, root_comment_id) {
          Ok(comment) -> {
            display_comment_with_replies(comment, comment_tree, user_data, 0)
          }
          Error(_) -> {
            io.println("✗ Could not find root comment: " <> root_comment_id)
          }
        }
      })
    }
    Ok(Error(msg)) -> {
      io.println("✗ Failed to retrieve comment tree: " <> msg)
    }
    Error(_) -> {
      io.println("✗ Comment tree retrieval timeout")
    }
  }
}

fn display_comment_with_replies(
  comment: Comment,
  comment_tree: CommentTree,
  user_data: UserTestData,
  depth: Int,
) {
  let indent = string.repeat("  ", depth)
  let username =
    get_username_by_id(user_data.user_id_to_name, comment.author_id)

  io.println(
    indent
    <> "└─ "
    <> username
    <> " (depth "
    <> int.to_string(comment.depth)
    <> "):",
  )
  io.println(indent <> "   \"" <> comment.content <> "\"")
  io.println(
    indent
    <> "   [ID: "
    <> comment.id
    <> ", Score: "
    <> int.to_string(comment.score)
    <> "]",
  )
  io.println("")

  // Display replies
  list.each(comment.replies, fn(reply_id) {
    case dict.get(comment_tree.comments, reply_id) {
      Ok(reply_comment) -> {
        display_comment_with_replies(
          reply_comment,
          comment_tree,
          user_data,
          depth + 1,
        )
      }
      Error(_) -> {
        io.println("✗ Could not find reply comment: " <> reply_id)
      }
    }
  })
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

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

// =============================================================================
// FEED FUNCTIONALITY TESTS
// =============================================================================

fn test_feed_functionality(
  engine_subject: process.Subject(MasterEngineMessage),
  user_data: UserTestData,
  subreddit_data: SubredditTestData,
) {
  io.println("")
  io.println("--- Testing Feed Functionality ---")

  // Create a second post to have 2 posts in the feed
  case get_user_by_index(user_data.user_ids, 0) {
    None -> {
      io.println("✗ User 1 not found, cannot create second post")
    }
    Some(author_id) -> {
      let reply = process.new_subject()
      let message =
        CreatePost(
          reply,
          "Second Test Post",
          "This is the second test post content for the feed",
          author_id,
          subreddit_data.subreddit_id,
        )

      let _ = process.send(engine_subject, message)

      case process.receive(reply, 1000) {
        Ok(Ok(post)) -> {
          io.println("✓ Second post created successfully!")
          io.println("  Title: " <> post.title)
          io.println("  Content: " <> post.content)
          io.println(
            "  Author: "
            <> get_username_by_id(user_data.user_id_to_name, post.author_id),
          )

          // Now test the feed functionality
          test_get_feed(engine_subject)
        }
        Ok(Error(msg)) -> {
          io.println("✗ Failed to create second post: " <> msg)
        }
        Error(_) -> {
          io.println("✗ Second post creation timeout")
        }
      }
    }
  }
}

fn test_get_feed(engine_subject: process.Subject(MasterEngineMessage)) {
  io.println("")
  io.println("📰 Testing Feed Retrieval...")

  let reply = process.new_subject()
  let message = GetFeed(reply, 10)
  // Get up to 10 posts

  let _ = process.send(engine_subject, message)

  case process.receive(reply, 1000) {
    Ok(Ok(feed_objects)) -> {
      let feed_count = list.length(feed_objects)
      io.println("✓ Feed retrieved successfully!")
      io.println("  Total posts in feed: " <> int.to_string(feed_count))
      io.println("")

      // Display each post in the feed
      list.each(feed_objects, fn(feed_object) {
        io.println("📄 Feed Post:")
        io.println("  Title: " <> feed_object.title)
        io.println("  Content: " <> feed_object.content)
        io.println("")
      })

      io.println("✓ Feed functionality test completed!")
    }
    Ok(Error(msg)) -> {
      io.println("✗ Failed to retrieve feed: " <> msg)
    }
    Error(_) -> {
      io.println("✗ Feed retrieval timeout")
    }
  }
}
