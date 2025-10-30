import gleam/list
import gleam/option.{None}
import reddit_simulator_gleam/scenario_types.{
  type ClientActionStep, type Scenario, ClientActionStep, Scenario,
}
import reddit_simulator_gleam/simulation_types.{
  type UserAction, CreateCommentAction, CreatePostAction,
  GetDirectMessagesAction, GetFeedAction, SendDirectMessageAction,
  SubscribeToSubredditAction,
}

// =============================================================================
// SCENARIO CONFIGS
// =============================================================================

pub fn ten_client_smoke_test() -> Scenario {
  let base_actions: List(UserAction) = [
    SubscribeToSubredditAction("subreddit_0"),
    SubscribeToSubredditAction("subreddit_1"),
    CreatePostAction("Hello World", "Intro post", "subreddit_0"),
    CreateCommentAction("Nice to meet you!", "subreddit_0", None),
    GetFeedAction,
    GetDirectMessagesAction,
    SendDirectMessageAction("user_1", "hey there"),
  ]

  // Build steps for 10 clients: indices 0..9
  let indices = list.range(0, 9)

  let steps =
    indices
    |> list.flat_map(fn(i) {
      base_actions
      |> list.map(fn(action) { ClientActionStep(i, action) })
    })

  Scenario(steps: steps)
}
