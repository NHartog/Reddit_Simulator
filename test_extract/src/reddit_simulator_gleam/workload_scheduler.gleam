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
  type SimulationConfig, type UserAction, type VoteType, CreateCommentAction,
  CreatePostAction, Downvote, GetDirectMessagesAction, GetFeedAction,
  SendDirectMessageAction, SubscribeToSubredditAction, Upvote,
  VoteOnCommentAction, VoteOnPostAction,
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
  let seed = case config.random_seed {
    0 -> {
      // Derive a seed from runtime randomness
      let u = float.random()
      int.max(1, floor_to_int(u *. 2_147_483_647.0))
    }
    n -> n
  }
  let rng0 = rng_seed(seed)
  let weights =
    compute_zipf_weights_varying(
      list.length(client_ids),
      config.zipf_alpha,
      rng0,
    )

  // Time-based ticks: use stats_update_interval_ms as tick length
  let tick_ms = case config.stats_update_interval_ms {
    0 -> 50
    n -> n
  }
  let ticks = int.max(1, config.simulation_duration_ms / tick_ms)

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

  // Initialise per-user RNG streams and Poisson next-due schedule
  let #(next_due_ms0, rngs0, rates_per_ms) =
    init_poisson_per_user(weights, seed)

  let final_stats =
    run_ticks(
      master_simulator,
      client_ids,
      weights,
      ticks,
      0,
      initial_stats,
      tick_ms,
      seed,
      0,
      next_due_ms0,
      rngs0,
      rates_per_ms,
      config,
      0,
    )

  let #(s1, s5, s10) = compute_top_k_shares(weights, list.length(client_ids))
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
  ticks: Int,
  current_time_ms: Int,
  stats: DispatchStats,
  tick_ms: Int,
  master_seed: Int,
  offset: Int,
  next_due_ms: List(Int),
  rngs: List(Rng),
  rates_per_ms: List(Float),
  config: SimulationConfig,
  check_counter: Int,
) -> DispatchStats {
  case ticks {
    0 -> stats
    _ -> {
      // Sleep for tick length to run for wall-clock duration
      let sleeper = process.new_subject()
      let _ = process.receive(sleeper, tick_ms)

      let now_ms = current_time_ms + tick_ms
      // Print periodic stats every 5 seconds
      let crossed = { now_ms / 5000 } > { current_time_ms / 5000 }
      let #(updated_counter, _) = case crossed {
        True -> {
          let new_check_counter = check_counter + 1
          let elapsed_sec = now_ms / 1000
          let actions_per_sec =
            int.to_float(stats.total_actions) /. int.to_float(elapsed_sec)
          io.println(
            "\n[check # "
            <> int.to_string(new_check_counter)
            <> "] "
            <> "Total Actions: "
            <> int.to_string(stats.total_actions)
            <> " | Rate: "
            <> float.to_string(actions_per_sec)
            <> " actions/sec\n"
            <> "  ├─ Posts: "
            <> int.to_string(stats.posts)
            <> " | Comments: "
            <> int.to_string(stats.comments)
            <> " | Votes: "
            <> int.to_string(stats.votes)
            <> "\n"
            <> "  ├─ Feeds: "
            <> int.to_string(stats.feeds)
            <> " | Direct Messages: "
            <> int.to_string(stats.dms)
            <> " | Subscriptions: "
            <> int.to_string(stats.subscriptions)
            <> "\n",
          )
          #(new_check_counter, Nil)
        }
        False -> #(check_counter, Nil)
      }

      // For each user: fire all actions due up to now (capped per tick)
      let fold_indices = list.range(0, list.length(client_ids) - 1)

      let updated =
        list.fold(fold_indices, #(stats, next_due_ms, rngs), fn(acc, idx) {
          let #(acc_stats, due_list, rng_list) = acc

          let due_opt = get_at(due_list, idx)
          let rng_opt = get_at(rng_list, idx)

          case #(due_opt, rng_opt, get_at(rates_per_ms, idx)) {
            #(Some(due0), Some(rng0), Some(rate_i)) -> {
              let fired =
                fire_due_actions(
                  master_simulator,
                  client_ids,
                  idx,
                  config,
                  now_ms,
                  rate_i,
                  20,
                  due0,
                  rng0,
                  acc_stats,
                )
              let #(stats2, due2, rng2) = fired
              let due_list2 = set_at(due_list, idx, due2)
              let rng_list2 = set_at(rng_list, idx, rng2)
              #(stats2, due_list2, rng_list2)
            }
            _ -> acc
          }
        })

      let #(new_stats, next_due_ms2, rngs2) = updated

      run_ticks(
        master_simulator,
        client_ids,
        weights,
        ticks - 1,
        now_ms,
        new_stats,
        tick_ms,
        master_seed,
        next_index(offset, list.length(client_ids)),
        next_due_ms2,
        rngs2,
        rates_per_ms,
        config,
        updated_counter,
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

fn fire_due_actions(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  client_index: Int,
  config: SimulationConfig,
  now_ms: Int,
  rate_per_ms: Float,
  cap: Int,
  due_ms: Int,
  rng: Rng,
  stats: DispatchStats,
) -> #(DispatchStats, Int, Rng) {
  case cap <= 0 || due_ms > now_ms {
    True -> #(stats, due_ms, rng)
    False -> {
      let #(action, rng2) = sample_action(config, rng)
      let _ =
        dispatch_action(master_simulator, client_ids, client_index, action)
      let stats2 = update_stats(stats, action)
      let #(delta_ms, rng3) = sample_exponential_ms(rng2, rate_per_ms)
      let due2 = due_ms + delta_ms
      fire_due_actions(
        master_simulator,
        client_ids,
        client_index,
        config,
        now_ms,
        rate_per_ms,
        cap - 1,
        due2,
        rng3,
        stats2,
      )
    }
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

// =============================================================================
// RANDOMIZED ACTION SELECTION
// =============================================================================

type Rng {
  Rng(state: Int)
}

fn rng_seed(seed: Int) -> Rng {
  Rng(state: seed)
}

fn stream_for_client(master_seed: Int, client_index: Int) -> Rng {
  let combined = master_seed + client_index * 1_001_001
  let a = 1_103_515_245
  let c = 12_345
  let m = 2_147_483_647
  let s_raw = a * combined + c
  let q = floor_div_int(s_raw, m)
  let s0 = s_raw - q * m
  let s = case s0 < 0 {
    True -> s0 + m
    False -> s0
  }
  rng_seed(s)
}

fn rng_next(r: Rng) -> Rng {
  // LCG parameters with 31-bit modulus
  let a = 1_103_515_245
  let c = 12_345
  let m = 2_147_483_647
  let s_raw = a * r.state + c
  let q = floor_div_int(s_raw, m)
  let s0 = s_raw - q * m
  let s = case s0 < 0 {
    True -> s0 + m
    False -> s0
  }
  Rng(state: s)
}

fn rng_float01(r: Rng) -> #(Float, Rng) {
  let m = 2_147_483_647
  let r2 = rng_next(r)
  let f = int.to_float(r2.state) /. int.to_float(m)
  #(f, r2)
}

// =============================================================================
// POISSON ARRIVALS HELPERS
// =============================================================================

fn init_poisson_per_user(
  weights: List(Float),
  master_seed: Int,
) -> #(List(Int), List(Rng), List(Float)) {
  // Target overall rate: 5000 actions/sec
  let target_rps = 5000.0
  let rates_per_sec = list.map(weights, fn(w) { target_rps *. w })
  let rates_per_ms = list.map(rates_per_sec, fn(r) { r /. 1000.0 })

  let indices = list.range(0, list.length(weights) - 1)
  let init =
    list.fold(indices, #([], [], []), fn(acc, idx) {
      let #(due_list, rng_list, rate_list) = acc
      let rng0 = stream_for_client(master_seed, idx)
      let rate_ms = with_default_opt(get_at(rates_per_ms, idx), 0.0)
      let #(delta_ms, rng1) = sample_exponential_ms(rng0, rate_ms)
      let due0 = delta_ms
      #([due0, ..due_list], [rng1, ..rng_list], [rate_ms, ..rate_list])
    })
  // Built in reverse; flip back
  let #(d_init, r_init, rate_init) = init
  #(list.reverse(d_init), list.reverse(r_init), list.reverse(rate_init))
}

fn sample_exponential_ms(rng: Rng, rate_per_ms: Float) -> #(Int, Rng) {
  case rate_per_ms <. 1.0e-12 {
    True -> #(10, rng)
    // fallback small delay if rate is zero or negative
    False -> {
      let #(u0, r2) = rng_float01(rng)
      // avoid zero
      let u = case u0 <. 1.0e-9 {
        True -> 1.0e-9
        False -> u0
      }
      let ln = case float.logarithm(u) {
        Ok(v) -> v
        Error(_) -> 0.0
      }
      let delta = { 0.0 -. ln } /. rate_per_ms
      let ms = int.max(1, floor_to_int(delta))
      #(ms, r2)
    }
  }
}

fn set_at(xs: List(a), index: Int, value: a) -> List(a) {
  set_at_loop(xs, index, 0, [], value)
}

fn set_at_loop(
  xs: List(a),
  target: Int,
  current: Int,
  acc: List(a),
  value: a,
) -> List(a) {
  case xs {
    [] -> list.reverse(acc)
    [h, ..t] -> {
      case current == target {
        True ->
          list.reverse([value, ..acc]) |> fn(prefix) { list.append(prefix, t) }
        False -> set_at_loop(t, target, current + 1, [h, ..acc], value)
      }
    }
  }
}

fn rng_int_range(r: Rng, min: Int, max: Int) -> #(Int, Rng) {
  let r2 = rng_next(r)
  let span = int.max(1, max - min + 1)
  let raw = r2.state
  let m = span
  let v0 = raw % m
  let v = case v0 < 0 {
    True -> v0 + m
    False -> v0
  }
  #(min + v, r2)
}

fn sample_action(config: SimulationConfig, r: Rng) -> #(UserAction, Rng) {
  // Build cumulative distribution from config
  let post_p = clampf(config.post_frequency)
  let comment_p = clampf(config.comment_frequency)
  let vote_p = clampf(config.vote_frequency)
  let dm_p = clampf(config.message_frequency)
  let feed_p = 0.2
  let sub_p = 0.1
  let total = post_p +. comment_p +. vote_p +. dm_p +. feed_p +. sub_p
  let #(u, r2a) = rng_float01(r)
  let x = u *. total
  // Choose random subreddit index and recipient/post ids where applicable
  let sub_max = int.max(1, config.num_subreddits) - 1
  let user_max = int.max(1, config.num_users) - 1
  let #(sub_idx, r2b) = rng_int_range(r2a, 0, sub_max)
  let subreddit_id = "subreddit_" <> int.to_string(sub_idx)
  case x <. post_p {
    True -> #(CreatePostAction("Zipf post", "content", subreddit_id), r2b)
    False -> {
      let t1 = post_p +. comment_p
      case x <. t1 {
        True -> #(CreateCommentAction("Zipf comment", subreddit_id, None), r2b)
        False -> {
          let t2 = t1 +. vote_p
          case x <. t2 {
            True -> sample_vote(config, r2b)
            False -> {
              let t3 = t2 +. dm_p
              case x <. t3 {
                True -> {
                  let #(u_idx, r2c) = rng_int_range(r2b, 0, user_max)
                  let recipient = "user_" <> int.to_string(u_idx)
                  #(SendDirectMessageAction(recipient, "hi"), r2c)
                }
                False -> {
                  let t4 = t3 +. feed_p
                  case x <. t4 {
                    True -> #(GetFeedAction, r2b)
                    False -> #(SubscribeToSubredditAction(subreddit_id), r2b)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn sample_vote(config: SimulationConfig, r: Rng) -> #(UserAction, Rng) {
  let #(choice, r2a) = rng_float01(r)
  // Choose a random post id in a broad range to spread interactions
  let #(post_num, r2b) = rng_int_range(r2a, 1, 100_000)
  let post_id = "post_" <> int.to_string(post_num)
  case choice <. 0.5 {
    True -> #(VoteOnPostAction(post_id, Upvote), r2b)
    False -> #(VoteOnPostAction(post_id, Downvote), r2b)
  }
}

fn clampf(p: Float) -> Float {
  case p <. 0.0 {
    True -> 0.0
    False -> {
      case p >. 1.0 {
        True -> 1.0
        False -> p
      }
    }
  }
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
    VoteOnPostAction(_, _) -> DispatchStats(..base, votes: base.votes + 1)
    VoteOnCommentAction(_, _) -> DispatchStats(..base, votes: base.votes + 1)
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
    "\nWorkload Summary\n"
    <> "  Total Actions: "
    <> int.to_string(stats.total_actions)
    <> "\n"
    <> "  ├─ Posts Created: "
    <> int.to_string(stats.posts)
    <> "\n"
    <> "  ├─ Comments Created: "
    <> int.to_string(stats.comments)
    <> "\n"
    <> "  ├─ Votes Cast: "
    <> int.to_string(stats.votes)
    <> "\n"
    <> "  ├─ Feed Retrievals: "
    <> int.to_string(stats.feeds)
    <> "\n"
    <> "  ├─ Direct Messages: "
    <> int.to_string(stats.dms)
    <> "\n"
    <> "  └─ Subscriptions: "
    <> int.to_string(stats.subscriptions)
    <> "\n"
    <> "  Activity Distribution (Zipf Top-K):\n"
    <> "    ├─ Top 1% of users: "
    <> float.to_string(stats.top1p_share *. 100.0)
    <> "% of activity\n"
    <> "    ├─ Top 5% of users: "
    <> float.to_string(stats.top5p_share *. 100.0)
    <> "% of activity\n"
    <> "    └─ Top 10% of users: "
    <> float.to_string(stats.top10p_share *. 100.0)
    <> "% of activity\n",
  )
}

fn compute_zipf_weights(n: Int, _alpha: Float) -> List(Float) {
  let ranks = list.range(1, n)
  let raw = list.map(ranks, fn(r) { 1.0 /. int.to_float(r) })
  let sum = list.fold(raw, 0.0, fn(acc, x) { acc +. x })
  list.map(raw, fn(x) { x /. sum })
}

fn compute_zipf_weights_varying(n: Int, alpha: Float, rng: Rng) -> List(Float) {
  // Vary alpha slightly and add small per-rank jitter; renormalize
  let #(u_eps, r2) = rng_float01(rng)
  let alpha_jitter = { u_eps *. 0.2 } -. 0.1
  let a = alpha +. alpha_jitter
  let ranks = list.range(1, n)
  let jittered =
    list.fold(ranks, #([], r2), fn(acc, r) {
      let xs = elem1(acc)
      let rr = elem2(acc)
      let #(u, rr2) = rng_float01(rr)
      let eps = { u *. 0.1 } -. 0.05
      let pow_res = float.power(int.to_float(r), a)
      let denom = case pow_res {
        Ok(v) -> v
        Error(_) -> 1.0
      }
      let base = 1.0 /. denom
      let w = base *. { 1.0 +. eps }
      #([w, ..xs], rr2)
    })
  let ws_rev = elem1(jittered)
  let ws = list.reverse(ws_rev)
  let sum = list.fold(ws, 0.0, fn(acc, x) { acc +. x })
  case sum <=. 0.0 {
    True -> compute_zipf_weights(n, alpha)
    False -> list.map(ws, fn(x) { x /. sum })
  }
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

fn compute_top_k_shares(
  weights: List(Float),
  total_users: Int,
) -> #(Float, Float, Float) {
  let sorted = list.sort(weights, fn(a, b) { float_compare_desc(a, b) })
  let len = list.length(sorted)
  case len {
    0 -> #(0.0, 0.0, 0.0)
    _ -> {
      // Use len (actual weights) not total_users to ensure we don't exceed bounds
      let n = int.max(1, len)
      let k1_raw = int.max(1, floor_div_int(n, 100))
      let k5_raw = int.max(1, floor_div_int(n * 5, 100))
      let k10_raw = int.max(1, floor_div_int(n * 10, 100))
      // Ensure k5 > k1 and k10 > k5 to get distinct sets
      let k1 = int.min(k1_raw, len)
      let k5_uncapped = int.max(k1 + 1, k5_raw)
      let k5 = int.min(k5_uncapped, len)
      let k10_uncapped = int.max(k5 + 1, k10_raw)
      let k10 = int.min(k10_uncapped, len)
      let sum_all = list.fold(sorted, 0.0, fn(acc, x) { acc +. x })
      case sum_all == 0.0 {
        True -> #(0.0, 0.0, 0.0)
        False -> {
          let top1 = take_first_n(sorted, k1)
          let top5 = take_first_n(sorted, k5)
          let top10 = take_first_n(sorted, k10)
          let s1 = list.fold(top1, 0.0, fn(acc, x) { acc +. x }) /. sum_all
          let s5 = list.fold(top5, 0.0, fn(acc, x) { acc +. x }) /. sum_all
          let s10 = list.fold(top10, 0.0, fn(acc, x) { acc +. x }) /. sum_all
          // Ensure monotonicity: top10 >= top5 >= top1
          let s5_corrected = float.max(s5, s1)
          let s10_corrected = float.max(s10, s5_corrected)
          #(s1, s5_corrected, s10_corrected)
        }
      }
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
