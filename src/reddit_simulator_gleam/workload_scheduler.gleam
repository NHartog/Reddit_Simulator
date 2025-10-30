import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/string
import reddit_simulator_gleam/master_simulator_actor.{
  type MasterSimulatorMessage, TriggerClientAction,
}
import reddit_simulator_gleam/simulation_types.{
  type SimulationConfig, type UserAction, CreateCommentAction, CreatePostAction,
  GetDirectMessagesAction, GetFeedAction, SendDirectMessageAction,
  SubscribeToSubredditAction,
}

// =============================================================================
// ZIPF-BASED WORKLOAD SCHEDULER (DETERMINISTIC, NO RNG)
// =============================================================================

pub type DispatchStats {
  DispatchStats(
    total_actions: Int,
    posts: Int,
    comments: Int,
    votes: Int,
    messages: Int,
    subscriptions: Int,
    feeds: Int,
    dms: Int,
    top1p_share: Float,
    top5p_share: Float,
    top10p_share: Float,
  )
}

pub fn run_zipf_workload(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  config: SimulationConfig,
) -> DispatchStats {
  let weights = compute_zipf_weights(list.length(client_ids), config.zipf_alpha)

  // Build a deterministic action cycle per client according to frequencies
  let action_cycle = build_action_cycle(config)

  // Time-based ticks: use stats_update_interval_ms as tick length
  let tick_ms = case config.stats_update_interval_ms {
    0 -> 50
    n -> n
  }
  let ticks = int.max(1, config.simulation_duration_ms / tick_ms)
  let top_k = clamp(1, list.length(client_ids), 50)

  let initial_stats =
    DispatchStats(
      total_actions: 0,
      posts: 0,
      comments: 0,
      votes: 0,
      messages: 0,
      subscriptions: 0,
      feeds: 0,
      dms: 0,
      top1p_share: 0.0,
      top5p_share: 0.0,
      top10p_share: 0.0,
    )

  let final_stats =
    run_ticks(
      master_simulator,
      client_ids,
      weights,
      action_cycle,
      ticks,
      top_k,
      0,
      initial_stats,
      tick_ms,
    )

  let #(s1, s5, s10) = compute_top_k_shares(weights)
  DispatchStats(
    ..final_stats,
    top1p_share: s1,
    top5p_share: s5,
    top10p_share: s10,
  )
}

fn run_ticks(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  weights: List(Float),
  action_cycle: List(UserAction),
  ticks: Int,
  top_k: Int,
  offset: Int,
  stats: DispatchStats,
  tick_ms: Int,
) -> DispatchStats {
  case ticks {
    0 -> stats
    _ -> {
      // Sleep for tick length to run for wall-clock duration
      let sleeper = process.new_subject()
      let _ = process.receive(sleeper, tick_ms)

      // Choose top_k clients each tick, rotate starting offset for fairness among equals
      let ranked = rank_clients(weights, offset)
      let chosen = take_first_n(map_fst_indices(ranked), top_k)

      let folded =
        list.fold(chosen, #(stats, 0), fn(state, client_index) {
          let acc_stats = elem1(state)
          let action_idx = elem2(state)
          let action =
            get_at(action_cycle, action_idx) |> with_default_opt(GetFeedAction)
          let _ =
            dispatch_action(master_simulator, client_ids, client_index, action)
          let updated_stats = update_stats(acc_stats, action)
          let next_idx = next_index(action_idx, list.length(action_cycle))
          #(updated_stats, next_idx)
        })

      let new_stats = elem1(folded)

      run_ticks(
        master_simulator,
        client_ids,
        weights,
        action_cycle,
        ticks - 1,
        top_k,
        next_index(offset, list.length(client_ids)),
        new_stats,
        tick_ms,
      )
    }
  }
}

fn dispatch_action(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  client_index: Int,
  action: UserAction,
) -> Nil {
  case get_at(client_ids, client_index) {
    Some(client_id) -> {
      let _ =
        process.send(master_simulator, TriggerClientAction(client_id, action))
      Nil
    }
    None -> Nil
  }
}

fn build_action_cycle(config: SimulationConfig) -> List(UserAction) {
  // Build a 20-slot cycle approximating frequencies deterministically
  let post_slots = 6
  let comment_slots = 6
  let message_slots = 2
  let feed_slots = 4
  let sub_slots = 2

  let subreddit = "subreddit_0"
  let a1 =
    repeat_n(CreatePostAction("Zipf post", "content", subreddit), post_slots)
  let a2 =
    repeat_n(
      CreateCommentAction("Zipf comment", subreddit, None),
      comment_slots,
    )
  let a3 = repeat_n(SendDirectMessageAction("user_1", "hi"), message_slots)
  let a4 = repeat_n(GetFeedAction, feed_slots)
  let a5 = repeat_n(SubscribeToSubredditAction(subreddit), sub_slots)
  let actions =
    list.append(list.append(a1, a2), list.append(list.append(a3, a4), a5))

  actions
}

fn update_stats(stats: DispatchStats, action: UserAction) -> DispatchStats {
  let base =
    DispatchStats(
      total_actions: stats.total_actions + 1,
      posts: stats.posts,
      comments: stats.comments,
      votes: stats.votes,
      messages: stats.messages,
      subscriptions: stats.subscriptions,
      feeds: stats.feeds,
      dms: stats.dms,
      top1p_share: stats.top1p_share,
      top5p_share: stats.top5p_share,
      top10p_share: stats.top10p_share,
    )

  case action {
    CreatePostAction(_, _, _) -> DispatchStats(..base, posts: base.posts + 1)
    CreateCommentAction(_, _, _) ->
      DispatchStats(..base, comments: base.comments + 1)
    SendDirectMessageAction(_, _) -> DispatchStats(..base, dms: base.dms + 1)
    SubscribeToSubredditAction(_) ->
      DispatchStats(..base, subscriptions: base.subscriptions + 1)
    GetFeedAction -> DispatchStats(..base, feeds: base.feeds + 1)
    GetDirectMessagesAction ->
      DispatchStats(..base, messages: base.messages + 1)
    _ -> base
  }
}

pub fn print_summary(stats: DispatchStats) {
  io.println(
    "📊 Summary: actions="
    <> int.to_string(stats.total_actions)
    <> " posts="
    <> int.to_string(stats.posts)
    <> " comments="
    <> int.to_string(stats.comments)
    <> " feed="
    <> int.to_string(stats.feeds)
    <> " dms="
    <> int.to_string(stats.dms)
    <> " subs="
    <> int.to_string(stats.subscriptions)
    <> " votes="
    <> int.to_string(stats.votes)
    <> " | top1%="
    <> float.to_string(stats.top1p_share)
    <> " top5%="
    <> float.to_string(stats.top5p_share)
    <> " top10%="
    <> float.to_string(stats.top10p_share),
  )
}

fn compute_zipf_weights(n: Int, _alpha: Float) -> List(Float) {
  let ranks = list.range(1, n)
  let raw = list.map(ranks, fn(r) { 1.0 /. int.to_float(r) })
  let sum = list.fold(raw, 0.0, fn(acc, x) { acc +. x })
  list.map(raw, fn(x) { x /. sum })
}

fn rank_clients(weights: List(Float), offset: Int) -> List(#(Int, Float)) {
  let indexed = index_list(weights)
  // Sort descending by weight
  let sorted =
    list.sort(indexed, fn(a, b) { float_compare_desc(elem2(a), elem2(b)) })
  // Rotate by offset for fairness
  rotate_pairs(sorted, offset)
}

fn map_fst_indices(pairs: List(#(Int, Float))) -> List(Int) {
  list.map(pairs, fn(p) { elem1(p) })
}

fn take_first_n(xs: List(a), n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False -> take_loop(xs, n, [])
  }
}

fn take_loop(xs: List(a), n: Int, acc: List(a)) -> List(a) {
  case xs {
    [] -> list.reverse(acc)
    [h, ..t] -> {
      case n == 0 {
        True -> list.reverse(acc)
        False -> take_loop(t, n - 1, [h, ..acc])
      }
    }
  }
}

fn index_list(xs: List(a)) -> List(#(Int, a)) {
  index_list_loop(xs, 0, [])
}

fn index_list_loop(xs: List(a), i: Int, acc: List(#(Int, a))) -> List(#(Int, a)) {
  case xs {
    [] -> list.reverse(acc)
    [h, ..t] -> index_list_loop(t, i + 1, [#(i, h), ..acc])
  }
}

fn rotate_pairs(xs: List(#(Int, Float)), offset: Int) -> List(#(Int, Float)) {
  let len = list.length(xs)
  case len {
    0 -> []
    _ -> {
      let o = offset % len
      let pair = split_at(xs, o)
      let left = elem1(pair)
      let right = elem2(pair)
      list.append(right, left)
    }
  }
}

fn split_at(xs: List(a), n: Int) -> #(List(a), List(a)) {
  split_loop(xs, n, [])
}

fn split_loop(xs: List(a), n: Int, acc: List(a)) -> #(List(a), List(a)) {
  case xs {
    [] -> #(list.reverse(acc), [])
    [h, ..t] -> {
      case n <= 0 {
        True -> #(list.reverse(acc), xs)
        False -> split_loop(t, n - 1, [h, ..acc])
      }
    }
  }
}

fn float_compare_desc(a: Float, b: Float) -> Order {
  case float.compare(a, b) {
    Lt -> Gt
    Gt -> Lt
    Eq -> Eq
  }
}

fn compute_top_k_shares(weights: List(Float)) -> #(Float, Float, Float) {
  let sorted = list.sort(weights, fn(a, b) { float_compare_desc(a, b) })
  let len = list.length(sorted)
  case len {
    0 -> #(0.0, 0.0, 0.0)
    _ -> {
      let k1 = int.max(1, floor_div_int(len, 100))
      let k5 = int.max(1, floor_div_int(len * 5, 100))
      let k10 = int.max(1, floor_div_int(len * 10, 100))
      let sum_all = list.fold(sorted, 0.0, fn(acc, x) { acc +. x })
      let top1 = take_first_n(sorted, k1)
      let top5 = take_first_n(sorted, k5)
      let top10 = take_first_n(sorted, k10)
      let s1 = list.fold(top1, 0.0, fn(acc, x) { acc +. x }) /. sum_all
      let s5 = list.fold(top5, 0.0, fn(acc, x) { acc +. x }) /. sum_all
      let s10 = list.fold(top10, 0.0, fn(acc, x) { acc +. x }) /. sum_all
      #(s1, s5, s10)
    }
  }
}

fn floor_div_int(a: Int, b: Int) -> Int {
  floor_to_int(int.to_float(a) /. int.to_float(b))
}

fn floor_to_int(x: Float) -> Int {
  let s = float.to_string(x)
  let parts = string.split(s, ".")
  case parts {
    [] -> 0
    [whole] -> parse_int_or_zero(whole)
    [whole, ..] -> parse_int_or_zero(whole)
  }
}

fn parse_int_or_zero(s: String) -> Int {
  case int.parse(s) {
    Ok(v) -> v
    Error(_) -> 0
  }
}

fn repeat_n(a: a, n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False -> [a, ..repeat_n(a, n - 1)]
  }
}

fn clamp(min: Int, max: Int, value: Int) -> Int {
  case value < min {
    True -> min
    False -> {
      case value > max {
        True -> max
        False -> value
      }
    }
  }
}

fn elem1(t: #(a, b)) -> a {
  t.0
}

fn elem2(t: #(a, b)) -> b {
  t.1
}

fn elem3(t: #(a, b, c)) -> c {
  t.2
}

fn with_default_opt(res: Option(a), default: a) -> a {
  case res {
    Some(x) -> x
    None -> default
  }
}

fn get_at(items: List(a), index: Int) -> Option(a) {
  get_at_loop(items, index, 0)
}

fn get_at_loop(items: List(a), target: Int, current: Int) -> Option(a) {
  case items {
    [] -> None
    [head, ..tail] -> {
      case current == target {
        True -> Some(head)
        False -> get_at_loop(tail, target, current + 1)
      }
    }
  }
}

fn next_index(i: Int, len: Int) -> Int {
  case i + 1 >= len {
    True -> 0
    False -> i + 1
  }
}
