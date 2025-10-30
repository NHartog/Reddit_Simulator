import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import reddit_simulator_gleam/master_simulator_actor.{
  type MasterSimulatorMessage, TriggerClientAction,
}
import reddit_simulator_gleam/scenario_types.{
  type ClientActionStep, type Scenario,
}

// =============================================================================
// SCENARIO RUNNER
// =============================================================================

pub fn run_scenario(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  scenario: Scenario,
) {
  io.println("🎯 Running scenario steps...")

  scenario.steps
  |> list.each(fn(step) {
    let _ = send_step(master_simulator, client_ids, step)
    Nil
  })

  io.println("✅ Scenario steps dispatched")
}

fn send_step(
  master_simulator: process.Subject(MasterSimulatorMessage),
  client_ids: List(String),
  step: ClientActionStep,
) -> Nil {
  case get_at(client_ids, step.client_index) {
    None ->
      io.println(
        "❌ Scenario: client index out of range: "
        <> int.to_string(step.client_index),
      )
    Some(client_id) -> {
      let _ =
        process.send(
          master_simulator,
          TriggerClientAction(client_id, step.action),
        )
      Nil
    }
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
