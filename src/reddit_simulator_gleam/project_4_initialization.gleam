import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import reddit_simulator_gleam/engine_types.{
  type MasterEngineMessage, CreateSubreddit, RegisterUser,
}
import reddit_simulator_gleam/fake_client_actor.{
  type FakeClientMessage, create_fake_client_actor,
}
import reddit_simulator_gleam/master_engine_actor.{create_master_engine_actor}
import reddit_simulator_gleam/master_simulator_actor.{
  type MasterSimulatorMessage, AddClient, ConnectToEngine, Shutdown,
  StartSimulation, StopSimulation, TriggerClientAction,
  create_master_simulator_actor,
}

// import reddit_simulator_gleam/scenario_config
// import reddit_simulator_gleam/scenario_runner
import reddit_simulator_gleam/metrics_actor
import reddit_simulator_gleam/simulation_types.{
  CreateCommentAction, CreatePostAction, SendDirectMessageAction,
  SubscribeToSubredditAction, Upvote, VoteOnPostAction,
}
import reddit_simulator_gleam/workload_scheduler

// =============================================================================
// PROJECT 4 INITIALIZATION AND TESTING
// =============================================================================

pub fn initialize_simulation_system() -> Result(SimulationSystem, String) {
  io.println("🚀 PROJECT 4: Initializing simulation system...")

  // Step 1: Create Master Engine Actor
  case create_master_engine_actor() {
    Ok(master_engine) -> {
      io.println("✅ Master Engine Actor created successfully")

      // Step 2: Create Master Simulator Actor
      case create_master_simulator_actor() {
        Ok(master_simulator) -> {
          io.println("✅ Master Simulator Actor created successfully")

          // Step 3: Connect simulator to engine
          let _ = process.send(master_simulator, ConnectToEngine(master_engine))
          io.println("✅ Simulator connected to engine")

          // Step 3b: Create metrics actor and connect
          let metrics_opt = case metrics_actor.create_metrics_actor() {
            Ok(metrics) -> {
              let _ =
                process.send(
                  master_simulator,
                  master_simulator_actor.ConnectToMetrics(metrics),
                )
              io.println("✅ Simulator connected to metrics")
              // Connect metrics to engine
              let _ =
                process.send(
                  master_engine,
                  engine_types.ConnectMetrics(metrics),
                )
              Some(metrics)
            }
            Error(msg) -> {
              io.println("❌ Failed to create metrics actor: " <> msg)
              None
            }
          }

          // Step 4: Create simulation configuration
          let config = create_test_simulation_config()

          // Step 5: Create and register fake clients
          case create_and_register_clients(master_simulator, config) {
            Ok(client_data) -> {
              io.println("✅ Fake clients created and registered")

              let system =
                SimulationSystem(
                  master_engine: master_engine,
                  master_simulator: master_simulator,
                  metrics: metrics_opt,
                  clients: client_data.clients,
                  config: config,
                  is_initialized: True,
                )

              // Step 6: Set up initial data (users, subreddits)
              setup_initial_data(system)

              Ok(system)
            }
            Error(msg) -> Error("Failed to create clients: " <> msg)
          }
        }
        Error(msg) -> Error("Failed to create master simulator: " <> msg)
      }
    }
    Error(msg) -> Error("Failed to create master engine: " <> msg)
  }
}

pub type SimulationSystem {
  SimulationSystem(
    master_engine: process.Subject(MasterEngineMessage),
    master_simulator: process.Subject(MasterSimulatorMessage),
    metrics: Option(process.Subject(metrics_actor.MetricsMessage)),
    clients: List(ClientData),
    config: simulation_types.SimulationConfig,
    is_initialized: Bool,
  )
}

pub type ClientData {
  ClientData(
    client_id: String,
    user_id: String,
    client_actor: process.Subject(FakeClientMessage),
  )
}

// =============================================================================
// SIMULATION CONFIGURATION
// =============================================================================

fn create_test_simulation_config() -> simulation_types.SimulationConfig {
  simulation_types.SimulationConfig(
    num_users: 10_000,
    num_subreddits: 2000,
    simulation_duration_ms: 60_000,
    // 1 minute
    // 30 seconds
    zipf_alpha: 1.5,
    connection_probability: 0.8,
    post_frequency: 0.3,
    comment_frequency: 0.4,
    vote_frequency: 0.5,
    message_frequency: 0.1,
    high_activity_threshold: 10,
    max_posts_per_user: 5,
    max_comments_per_user: 10,
    repost_probability: 0.1,
    enable_real_time_stats: True,
    stats_update_interval_ms: 250,
    actor_timeout_ms: 5000,
    max_concurrent_operations: 10,
    random_seed: 22,
    enable_heterogeneity: False,
  )
}

// =============================================================================
// CLIENT CREATION AND REGISTRATION
// =============================================================================

fn create_and_register_clients(
  master_simulator: process.Subject(MasterSimulatorMessage),
  config: simulation_types.SimulationConfig,
) -> Result(ClientList, String) {
  let num_clients = config.num_users
  let client_data = []

  case
    create_clients_recursive(
      client_data,
      num_clients,
      config,
      master_simulator,
      0,
    )
  {
    Ok(clients) -> {
      let client_list = ClientList(clients: clients)
      Ok(client_list)
    }
    Error(msg) -> Error(msg)
  }
}

type ClientList {
  ClientList(clients: List(ClientData))
}

fn create_clients_recursive(
  acc_clients: List(ClientData),
  remaining_clients: Int,
  config: simulation_types.SimulationConfig,
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_index: Int,
) -> Result(List(ClientData), String) {
  case remaining_clients {
    0 -> Ok(acc_clients)
    _ -> {
      let client_id = "client_" <> int.to_string(client_index)
      let user_id = "user_" <> int.to_string(client_index)

      case create_fake_client_actor(user_id, config) {
        Ok(client_actor) -> {
          // Register client with master simulator
          let _ =
            process.send(master_simulator, AddClient(client_id, client_actor))

          let client_data =
            ClientData(
              client_id: client_id,
              user_id: user_id,
              client_actor: client_actor,
            )

          let new_acc = [client_data, ..acc_clients]
          create_clients_recursive(
            new_acc,
            remaining_clients - 1,
            config,
            master_simulator,
            client_index + 1,
          )
        }
        Error(msg) ->
          Error("Failed to create client " <> client_id <> ": " <> msg)
      }
    }
  }
}

// =============================================================================
// INITIAL DATA SETUP
// =============================================================================

fn setup_initial_data(system: SimulationSystem) {
  io.println("🔧 PROJECT 4: Setting up initial data...")

  // Register users with the engine
  list.each(system.clients, fn(client_data) {
    register_user_with_engine(system.master_engine, client_data.user_id)
  })

  // Create initial subreddits
  create_initial_subreddits(system.master_engine, system.config.num_subreddits)

  io.println("✅ Initial data setup completed")
}

fn register_user_with_engine(
  master_engine: process.Subject(MasterEngineMessage),
  user_id: String,
) {
  let reply = process.new_subject()
  let username = "user_" <> user_id
  let email = username <> "@example.com"
  let message = RegisterUser(reply, username, email)

  let _ = process.send(master_engine, message)

  // Wait for response (in a real implementation, this would be handled asynchronously)
  case process.receive(reply, 5000) {
    Ok(registered_user_id) -> {
      io.println("👤 User registered: " <> registered_user_id)
    }
    Error(_) -> {
      io.println("❌ Failed to register user: " <> user_id)
    }
  }
}

fn create_initial_subreddits(
  master_engine: process.Subject(MasterEngineMessage),
  num_subreddits: Int,
) {
  list.range(0, num_subreddits - 1)
  |> list.map(fn(index) {
    let subreddit_name = "subreddit_" <> int.to_string(index)
    let description = "Test subreddit " <> int.to_string(index)
    let creator_id = "user_0"
    // Use first user as creator

    let reply = process.new_subject()
    let message =
      CreateSubreddit(reply, subreddit_name, description, creator_id)

    let _ = process.send(master_engine, message)

    case process.receive(reply, 5000) {
      Ok(Ok(subreddit)) -> {
        io.println("📋 Subreddit created: " <> subreddit.name)
        subreddit.id
      }
      Ok(Error(msg)) -> {
        io.println(
          "❌ Failed to create subreddit " <> subreddit_name <> ": " <> msg,
        )
        ""
      }
      Error(_) -> {
        io.println("❌ Timeout creating subreddit " <> subreddit_name)
        ""
      }
    }
  })
  |> list.filter(fn(id) { id != "" })
  |> list.length
  |> fn(count) {
    io.println("📋 Created " <> int.to_string(count) <> " subreddits")
  }
}

// =============================================================================
// SIMULATION CONTROL FUNCTIONS
// =============================================================================

pub fn start_simulation(system: SimulationSystem) {
  io.println("🚀 PROJECT 4: Starting simulation...")
  let _ = process.send(system.master_simulator, StartSimulation(system.config))
  io.println("✅ Simulation started")
}

pub fn stop_simulation(system: SimulationSystem) {
  io.println("⏹️ PROJECT 4: Stopping simulation...")
  let _ = process.send(system.master_simulator, StopSimulation)
  io.println("✅ Simulation stopped")
}

pub fn trigger_test_actions(system: SimulationSystem) {
  io.println("🎯 PROJECT 4: Triggering test actions...")

  // Trigger some test actions on different clients
  case system.clients {
    [] -> io.println("❌ No clients available for testing")
    [first_client, ..rest_clients] -> {
      // Test post creation
      let post_action =
        CreatePostAction("Test Post", "This is a test post", "subreddit_0")
      let _ =
        process.send(
          system.master_simulator,
          TriggerClientAction(first_client.client_id, post_action),
        )

      // Test comment creation
      case rest_clients {
        [] -> #()
        [second_client, ..] -> {
          let comment_action =
            CreateCommentAction("Test comment", "subreddit_0", None)
          let _ =
            process.send(
              system.master_simulator,
              TriggerClientAction(second_client.client_id, comment_action),
            )
          #()
        }
      }

      // Test voting
      case rest_clients {
        [] -> #()
        [_] -> #()
        [_, third_client, ..] -> {
          let vote_action = VoteOnPostAction("post_1", Upvote)
          let _ =
            process.send(
              system.master_simulator,
              TriggerClientAction(third_client.client_id, vote_action),
            )
          #()
        }
      }

      // Test direct message
      case rest_clients {
        [] -> #()
        [_] -> #()
        [_, _] -> #()
        [_, _, fourth_client, ..] -> {
          let dm_action = SendDirectMessageAction("user_1", "Test message")
          let _ =
            process.send(
              system.master_simulator,
              TriggerClientAction(fourth_client.client_id, dm_action),
            )
          #()
        }
      }

      // Test subscription
      case rest_clients {
        [] -> #()
        [_] -> #()
        [_, _] -> #()
        [_, _, _] -> #()
        [_, _, _, fifth_client, ..] -> {
          let sub_action = SubscribeToSubredditAction("subreddit_1")
          let _ =
            process.send(
              system.master_simulator,
              TriggerClientAction(fifth_client.client_id, sub_action),
            )
          #()
        }
      }

      io.println("✅ Test actions triggered")
    }
  }
}

// =============================================================================
// CLEANUP FUNCTIONS
// =============================================================================

pub fn shutdown_simulation_system(system: SimulationSystem) {
  io.println("🔌 PROJECT 4: Shutting down simulation system...")

  // Stop simulation first
  let _ = process.send(system.master_simulator, StopSimulation)

  // Shutdown master simulator (this will also shutdown all clients)
  let _ = process.send(system.master_simulator, Shutdown)

  // Shutdown master engine
  let _ = process.send(system.master_engine, engine_types.Shutdown)

  io.println("✅ Simulation system shutdown completed")
}

// =============================================================================
// DEMO FUNCTIONS
// =============================================================================

pub fn run_demo_simulation() {
  io.println("🎬 PROJECT 4: Running demo simulation...")

  case initialize_simulation_system() {
    Ok(system) -> {
      io.println("✅ System initialized successfully")

      // Start simulation
      start_simulation(system)

      // Zipf-based workload (skewed activity)
      let client_ids = list.map(system.clients, fn(c) { c.client_id })
      let stats =
        workload_scheduler.run_zipf_workload(
          system.master_simulator,
          client_ids,
          system.config,
        )

      // Stop simulation
      stop_simulation(system)

      // Allow clients to settle
      let settle1 = process.new_subject()
      let _ = process.receive(settle1, 150)

      // Shutdown system so no more logs interleave
      shutdown_simulation_system(system)

      // Consolidated final report after shutdown
      let settle2 = process.new_subject()
      let _ = process.receive(settle2, 200)
      io.println("================ Final Simulation Report ================")
      workload_scheduler.print_summary(stats)
      case system.metrics {
        None -> Nil
        Some(m) -> {
          let r = process.new_subject()
          let _ = process.send(m, metrics_actor.Snapshot(r))
          case process.receive(r, 1000) {
            Ok(snap) -> {
              io.println(
                "Throughput pps(1/10/60)="
                <> float.to_string(snap.posts_per_sec_1s)
                <> "/"
                <> float.to_string(snap.posts_per_sec_10s)
                <> "/"
                <> float.to_string(snap.posts_per_sec_60s)
                <> " rps(1/10/60)="
                <> float.to_string(snap.reads_per_sec_1s)
                <> "/"
                <> float.to_string(snap.reads_per_sec_10s)
                <> "/"
                <> float.to_string(snap.reads_per_sec_60s)
                <> " | latency post p50/p90/p99/p999="
                <> int.to_string(snap.post_p50_ms)
                <> "/"
                <> int.to_string(snap.post_p90_ms)
                <> "/"
                <> int.to_string(snap.post_p99_ms)
                <> "/"
                <> int.to_string(snap.post_p999_ms)
                <> " read p50/p90/p99/p999="
                <> int.to_string(snap.read_p50_ms)
                <> "/"
                <> int.to_string(snap.read_p90_ms)
                <> "/"
                <> int.to_string(snap.read_p99_ms)
                <> "/"
                <> int.to_string(snap.read_p999_ms)
                <> " | posts top1%/5%/10%="
                <> float.to_string(snap.posts_top1p_share)
                <> "/"
                <> float.to_string(snap.posts_top5p_share)
                <> "/"
                <> float.to_string(snap.posts_top10p_share),
              )
              Nil
            }
            Error(_) -> Nil
          }
        }
      }
      io.println("=========================================================")

      io.println("🎉 Demo simulation completed!")
    }
    Error(msg) -> {
      io.println("❌ Failed to initialize simulation system: " <> msg)
    }
  }
}
