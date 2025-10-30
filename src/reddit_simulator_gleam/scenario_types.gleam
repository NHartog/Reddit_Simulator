import reddit_simulator_gleam/simulation_types.{type UserAction}

// =============================================================================
// SCENARIO TYPES
// =============================================================================

pub type ClientActionStep {
  ClientActionStep(client_index: Int, action: UserAction)
}

pub type Scenario {
  Scenario(steps: List(ClientActionStep))
}
