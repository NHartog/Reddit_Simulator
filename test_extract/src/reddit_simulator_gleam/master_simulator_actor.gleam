import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import reddit_simulator_gleam/engine_types.{type MasterEngineMessage}
import reddit_simulator_gleam/fake_client_actor.{type FakeClientMessage}
import reddit_simulator_gleam/metrics_actor.{type MetricsMessage}
import reddit_simulator_gleam/simulation_types.{
  type SimulationConfig, type UserAction,
}

// =============================================================================
// MASTER SIMULATOR ACTOR TYPES
// =============================================================================

pub type MasterSimulatorMessage {
  StartSimulation(config: SimulationConfig)
  StopSimulation
  AddClient(client_id: String, client: process.Subject(FakeClientMessage))
  ConnectToEngine(engine: process.Subject(MasterEngineMessage))
  ConnectToMetrics(metrics: process.Subject(MetricsMessage))
  TriggerClientAction(client_id: String, action: UserAction)
  Shutdown
}

pub type MasterSimulatorState {
  MasterSimulatorState(
    config: Option(SimulationConfig),
    is_running: Bool,
    master_engine: Option(process.Subject(MasterEngineMessage)),
    metrics: Option(process.Subject(MetricsMessage)),
    clients: Dict(String, process.Subject(FakeClientMessage)),
  )
}

// =============================================================================
// MASTER SIMULATOR ACTOR IMPLEMENTATION
// =============================================================================

pub fn create_master_simulator_actor() -> Result(
  process.Subject(MasterSimulatorMessage),
  String,
) {
  let initial_state =
    MasterSimulatorState(
      config: None,
      is_running: False,
      master_engine: None,
      metrics: None,
      clients: dict.new(),
    )

  case
    actor.new(initial_state)
    |> actor.on_message(handle_master_simulator_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start MasterSimulatorActor: " <> error_to_string(err))
  }
}

fn handle_master_simulator_message(
  state: MasterSimulatorState,
  message: MasterSimulatorMessage,
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  case message {
    StartSimulation(config) -> {
      handle_start_simulation(state, config)
    }

    StopSimulation -> {
      handle_stop_simulation(state)
    }

    AddClient(client_id, client) -> {
      handle_add_client(state, client_id, client)
    }

    ConnectToEngine(engine) -> {
      handle_connect_to_engine(state, engine)
    }

    ConnectToMetrics(metrics) -> {
      handle_connect_to_metrics(state, metrics)
    }

    TriggerClientAction(client_id, action) -> {
      handle_trigger_client_action(state, client_id, action)
    }

    Shutdown -> {
      handle_shutdown(state)
    }
  }
}

// =============================================================================
// SIMULATION CONTROL HANDLERS
// =============================================================================

fn handle_start_simulation(
  state: MasterSimulatorState,
  config: SimulationConfig,
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  let new_state =
    MasterSimulatorState(
      config: Some(config),
      is_running: True,
      master_engine: state.master_engine,
      metrics: state.metrics,
      clients: state.clients,
    )

  // Start all clients
  dict.values(state.clients)
  |> list.map(fn(client) {
    let _ = process.send(client, fake_client_actor.StartSimulation)
    #()
  })

  actor.continue(new_state)
}

fn handle_stop_simulation(
  state: MasterSimulatorState,
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  let new_state =
    MasterSimulatorState(
      config: state.config,
      is_running: False,
      master_engine: state.master_engine,
      metrics: state.metrics,
      clients: state.clients,
    )

  // Stop all clients
  dict.values(state.clients)
  |> list.map(fn(client) {
    let _ = process.send(client, fake_client_actor.StopSimulation)
    #()
  })

  actor.continue(new_state)
}

// =============================================================================
// CLIENT MANAGEMENT HANDLERS
// =============================================================================

fn handle_add_client(
  state: MasterSimulatorState,
  client_id: String,
  client: process.Subject(FakeClientMessage),
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  let new_clients = dict.insert(state.clients, client_id, client)
  let new_state =
    MasterSimulatorState(
      config: state.config,
      is_running: state.is_running,
      master_engine: state.master_engine,
      metrics: state.metrics,
      clients: new_clients,
    )

  // Connect client to engine if available
  case state.master_engine {
    Some(engine) -> {
      let _ = process.send(client, fake_client_actor.ConnectToEngine(engine))
      #()
    }
    None -> #()
  }

  // Connect client to metrics if available
  case state.metrics {
    Some(m) -> {
      let _ = process.send(client, fake_client_actor.ConnectToMetrics(m))
      #()
    }
    None -> #()
  }

  // If simulation is running, start the client
  case state.is_running {
    True -> {
      let _ = process.send(client, fake_client_actor.StartSimulation)
      actor.continue(new_state)
    }
    False -> actor.continue(new_state)
  }
}

fn handle_connect_to_engine(
  state: MasterSimulatorState,
  engine: process.Subject(MasterEngineMessage),
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  let new_state =
    MasterSimulatorState(
      config: state.config,
      is_running: state.is_running,
      master_engine: Some(engine),
      metrics: state.metrics,
      clients: state.clients,
    )

  // Propagate engine to all existing clients
  dict.values(state.clients)
  |> list.map(fn(client) {
    let _ = process.send(client, fake_client_actor.ConnectToEngine(engine))
    #()
  })

  actor.continue(new_state)
}

fn handle_connect_to_metrics(
  state: MasterSimulatorState,
  metrics: process.Subject(MetricsMessage),
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  let new_state =
    MasterSimulatorState(
      config: state.config,
      is_running: state.is_running,
      master_engine: state.master_engine,
      metrics: Some(metrics),
      clients: state.clients,
    )

  // Propagate metrics to all existing clients
  dict.values(state.clients)
  |> list.map(fn(client) {
    let _ = process.send(client, fake_client_actor.ConnectToMetrics(metrics))
    #()
  })

  actor.continue(new_state)
}

fn handle_trigger_client_action(
  state: MasterSimulatorState,
  client_id: String,
  action: UserAction,
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  case dict.get(state.clients, client_id) {
    Error(_) -> {
      actor.continue(state)
    }
    Ok(client) -> {
      let _ = process.send(client, fake_client_actor.PerformAction(action))
      actor.continue(state)
    }
  }
}

fn handle_shutdown(
  state: MasterSimulatorState,
) -> actor.Next(MasterSimulatorState, MasterSimulatorMessage) {
  // Shutdown all clients
  dict.values(state.clients)
  |> list.map(fn(client) {
    let _ = process.send(client, fake_client_actor.Shutdown)
    #()
  })

  actor.stop()
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
