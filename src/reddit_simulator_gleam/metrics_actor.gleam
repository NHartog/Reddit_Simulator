import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string

// =============================================================================
// METRICS ACTOR: Rolling windows, throughput, latency percentiles
// =============================================================================

pub type MetricsEventType {
  Post
  Read
  Comment
  DM
}

pub type MetricsMessage {
  RecordEnqueue(
    event_type: MetricsEventType,
    subreddit: Option(String),
    user_id: String,
    enqueue_ms: Int,
  )
  RecordComplete(
    event_type: MetricsEventType,
    subreddit: Option(String),
    user_id: String,
    enqueue_ms: Int,
    complete_ms: Int,
  )
  Snapshot(reply: process.Subject(MetricsSnapshot))
  Shutdown
}

pub type MetricsSnapshot {
  MetricsSnapshot(
    // throughput overall (per second, last 1s/10s/60s)
    posts_per_sec_1s: Float,
    posts_per_sec_10s: Float,
    posts_per_sec_60s: Float,
    reads_per_sec_1s: Float,
    reads_per_sec_10s: Float,
    reads_per_sec_60s: Float,
    // latency percentiles overall for posts and reads
    post_p50_ms: Int,
    post_p90_ms: Int,
    post_p99_ms: Int,
    post_p999_ms: Int,
    read_p50_ms: Int,
    read_p90_ms: Int,
    read_p99_ms: Int,
    read_p999_ms: Int,
    // inequality/skew
    posts_gini_by_user: Float,
    posts_zipf_s: Float,
    posts_zipf_r2: Float,
    fano_posts_60s: Float,
    fano_reads_60s: Float,
    posts_top1p_share: Float,
    posts_top5p_share: Float,
    posts_top10p_share: Float,
  )
}

pub type MetricsState {
  MetricsState(
    now_ms: Int,
    // ring buffers of counts per second for 60 seconds
    posts_counts: List(Int),
    reads_counts: List(Int),
    // latency reservoirs (fixed-size recent samples)
    post_lat_ms: List(Int),
    read_lat_ms: List(Int),
    // per-entity counters
    posts_by_user: dict.Dict(String, Int),
    posts_by_subreddit: dict.Dict(String, Int),
    reads_by_user: dict.Dict(String, Int),
  )
}

pub fn create_metrics_actor() -> Result(process.Subject(MetricsMessage), String) {
  let initial_state =
    MetricsState(
      now_ms: 0,
      posts_counts: repeat_n(0, 60),
      reads_counts: repeat_n(0, 60),
      post_lat_ms: [],
      read_lat_ms: [],
      posts_by_user: dict.new(),
      posts_by_subreddit: dict.new(),
      reads_by_user: dict.new(),
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_message)
    |> actor.start()
  {
    Ok(a) -> Ok(a.data)
    Error(err) ->
      Error("Failed to start MetricsActor: " <> error_to_string(err))
  }
}

fn handle_message(
  state: MetricsState,
  message: MetricsMessage,
) -> actor.Next(MetricsState, MetricsMessage) {
  case message {
    RecordEnqueue(_type, _sub, _user, enqueue_ms) -> {
      let s = rotate_to(enqueue_ms, state)
      actor.continue(s)
    }
    RecordComplete(type_, subreddit_opt, user_id, enqueue_ms, complete_ms) -> {
      let s0 = rotate_to(complete_ms, state)
      let latency = int.max(0, complete_ms - enqueue_ms)
      let s1 = case type_ {
        Post -> incr_count(s0, Post) |> add_latency(Post, latency)
        Read -> incr_count(s0, Read) |> add_latency(Read, latency)
        Comment -> add_latency(s0, Post, latency)
        DM -> s0
      }
      // per-entity counters
      let s2 = case type_ {
        Post -> incr_post_entities(s1, user_id, subreddit_opt)
        Read -> incr_read_entities(s1, user_id)
        _ -> s1
      }
      actor.continue(s2)
    }
    Snapshot(reply) -> {
      let snapshot = build_snapshot(state)
      let _ = process.send(reply, snapshot)
      actor.continue(state)
    }
    Shutdown -> {
      io.println("🔌 METRICS: Shutting down")
      actor.stop()
    }
  }
}

fn rotate_to(now_ms: Int, state: MetricsState) -> MetricsState {
  let now_sec = now_ms / 1000
  let prev_sec = state.now_ms / 1000
  case now_sec == prev_sec {
    True -> state
    False -> {
      let steps = int.min(60, int.max(0, now_sec - prev_sec))
      let posts_c = advance_ring(state.posts_counts, steps)
      let reads_c = advance_ring(state.reads_counts, steps)
      MetricsState(
        now_ms: now_ms,
        posts_counts: posts_c,
        reads_counts: reads_c,
        post_lat_ms: state.post_lat_ms,
        read_lat_ms: state.read_lat_ms,
        posts_by_user: state.posts_by_user,
        posts_by_subreddit: state.posts_by_subreddit,
        reads_by_user: state.reads_by_user,
      )
    }
  }
}

fn incr_count(state: MetricsState, which: MetricsEventType) -> MetricsState {
  case which {
    Post -> {
      let bumped = bump_head(state.posts_counts)
      MetricsState(..state, posts_counts: bumped)
    }
    Read -> {
      let bumped = bump_head(state.reads_counts)
      MetricsState(..state, reads_counts: bumped)
    }
    Comment -> state
    DM -> state
  }
}

fn add_latency(
  state: MetricsState,
  which: MetricsEventType,
  ms: Int,
) -> MetricsState {
  let cap = 5000
  case which {
    Post ->
      MetricsState(
        ..state,
        post_lat_ms: push_bounded(state.post_lat_ms, ms, cap),
      )
    Read ->
      MetricsState(
        ..state,
        read_lat_ms: push_bounded(state.read_lat_ms, ms, cap),
      )
    Comment -> state
    DM -> state
  }
}

fn build_snapshot(state: MetricsState) -> MetricsSnapshot {
  let posts_1s = avg_over(state.posts_counts, 1)
  let posts_10s = avg_over(state.posts_counts, 10)
  let posts_60s = avg_over(state.posts_counts, 60)
  let reads_1s = avg_over(state.reads_counts, 1)
  let reads_10s = avg_over(state.reads_counts, 10)
  let reads_60s = avg_over(state.reads_counts, 60)

  let post_ps = percentiles(state.post_lat_ms)
  let read_ps = percentiles(state.read_lat_ms)
  let fano_posts = fano_index(state.posts_counts, 60)
  let fano_reads = fano_index(state.reads_counts, 60)
  let #(p1, p5, p10) = top_k_shares(dict.values(state.posts_by_user))

  MetricsSnapshot(
    posts_per_sec_1s: posts_1s,
    posts_per_sec_10s: posts_10s,
    posts_per_sec_60s: posts_60s,
    reads_per_sec_1s: reads_1s,
    reads_per_sec_10s: reads_10s,
    reads_per_sec_60s: reads_60s,
    post_p50_ms: elem1(post_ps),
    post_p90_ms: elem2(post_ps),
    post_p99_ms: elem3(post_ps),
    post_p999_ms: elem4(post_ps),
    read_p50_ms: elem1(read_ps),
    read_p90_ms: elem2(read_ps),
    read_p99_ms: elem3(read_ps),
    read_p999_ms: elem4(read_ps),
    posts_gini_by_user: 0.0,
    posts_zipf_s: 0.0,
    posts_zipf_r2: 0.0,
    fano_posts_60s: fano_posts,
    fano_reads_60s: fano_reads,
    posts_top1p_share: p1,
    posts_top5p_share: p5,
    posts_top10p_share: p10,
  )
}

fn advance_ring(xs: List(Int), steps: Int) -> List(Int) {
  case steps <= 0 {
    True -> xs
    False ->
      advance_ring(list.append(drop(xs, 0, steps), repeat_n(0, steps)), 0)
  }
}

fn bump_head(xs: List(Int)) -> List(Int) {
  case xs {
    [] -> []
    [h, ..t] -> [h + 1, ..t]
  }
}

fn avg_over(xs: List(Int), seconds: Int) -> Float {
  let n = int.max(1, int.min(60, seconds))
  let slice = take(xs, n)
  let sum = list.fold(slice, 0, fn(acc, v) { acc + v })
  int.to_float(sum) /. int.to_float(n)
}

fn percentiles(samples: List(Int)) -> #(Int, Int, Int, Int) {
  let sorted = list.sort(samples, fn(a, b) { int.compare(a, b) })
  let len = list.length(sorted)
  case len {
    0 -> #(0, 0, 0, 0)
    _ -> {
      let max_index = len - 1
      let idx50 = floor_div(max_index * 1, 2)
      let idx90 = floor_div(max_index * 9, 10)
      let idx99 = floor_div(max_index * 99, 100)
      let idx999 = floor_div(max_index * 999, 1000)
      let v50 = get_at(sorted, idx50) |> with_default(0)
      let v90 = get_at(sorted, idx90) |> with_default(0)
      let v99 = get_at(sorted, idx99) |> with_default(0)
      let v999 = get_at(sorted, idx999) |> with_default(0)
      #(v50, v90, v99, v999)
    }
  }
}

fn floor_div(a: Int, b: Int) -> Int {
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

fn push_bounded(xs: List(Int), v: Int, cap: Int) -> List(Int) {
  let all = [v, ..xs]
  let len = list.length(all)
  case len <= cap {
    True -> all
    False -> take(all, cap)
  }
}

fn take(xs: List(a), n: Int) -> List(a) {
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

fn drop(xs: List(a), n: Int, k: Int) -> List(a) {
  case k <= 0 {
    True -> xs
    False -> drop(tail(xs), n + 1, k - 1)
  }
}

fn tail(xs: List(a)) -> List(a) {
  case xs {
    [] -> []
    [_h, ..t] -> t
  }
}

fn repeat_n(a: a, n: Int) -> List(a) {
  case n <= 0 {
    True -> []
    False -> [a, ..repeat_n(a, n - 1)]
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

fn with_default(res: Option(a), default: a) -> a {
  case res {
    Some(x) -> x
    None -> default
  }
}

fn elem1(t: #(a, b, c, d)) -> a {
  t.0
}

fn elem2(t: #(a, b, c, d)) -> b {
  t.1
}

fn elem3(t: #(a, b, c, d)) -> c {
  t.2
}

fn elem4(t: #(a, b, c, d)) -> d {
  t.3
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}

fn incr_post_entities(
  state: MetricsState,
  user_id: String,
  subreddit: Option(String),
) -> MetricsState {
  let posts_by_user = dict_incr(state.posts_by_user, user_id)
  let posts_by_subreddit = case subreddit {
    None -> state.posts_by_subreddit
    Some(sub) -> dict_incr(state.posts_by_subreddit, sub)
  }
  MetricsState(
    ..state,
    posts_by_user: posts_by_user,
    posts_by_subreddit: posts_by_subreddit,
  )
}

fn incr_read_entities(state: MetricsState, user_id: String) -> MetricsState {
  let reads_by_user = dict_incr(state.reads_by_user, user_id)
  MetricsState(..state, reads_by_user: reads_by_user)
}

fn dict_incr(m: dict.Dict(String, Int), key: String) -> dict.Dict(String, Int) {
  case dict.get(m, key) {
    Ok(v) -> dict.insert(m, key, v + 1)
    Error(_) -> dict.insert(m, key, 1)
  }
}

fn fano_index(counts: List(Int), window: Int) -> Float {
  let n = int.max(1, int.min(window, list.length(counts)))
  let slice = take(counts, n)
  let mean =
    int.to_float(list.fold(slice, 0, fn(a, v) { a + v })) /. int.to_float(n)
  let var =
    list.fold(slice, 0.0, fn(a, v) {
      let d = int.to_float(v) -. mean
      let dd = d *. d
      a +. dd
    })
    /. int.to_float(n)
  case mean == 0.0 {
    True -> 0.0
    False -> var /. mean
  }
}

fn top_k_shares(counts: List(Int)) -> #(Float, Float, Float) {
  let sorted = list.sort(counts, fn(a, b) { int.compare(b, a) })
  let len = list.length(sorted)
  case len {
    0 -> #(0.0, 0.0, 0.0)
    _ -> {
      let total = int.to_float(list.fold(sorted, 0, fn(a, v) { a + v }))
      case total == 0.0 {
        True -> #(0.0, 0.0, 0.0)
        False -> {
          let k1 = int.max(1, floor_div(len, 100))
          let k5 = int.max(1, floor_div(len * 5, 100))
          let k10 = int.max(1, floor_div(len * 10, 100))
          let top1 = take(sorted, k1)
          let top5 = take(sorted, k5)
          let top10 = take(sorted, k10)
          let s1 = int.to_float(list.fold(top1, 0, fn(a, v) { a + v })) /. total
          let s5 = int.to_float(list.fold(top5, 0, fn(a, v) { a + v })) /. total
          let s10 =
            int.to_float(list.fold(top10, 0, fn(a, v) { a + v })) /. total
          #(s1, s5, s10)
        }
      }
    }
  }
}
