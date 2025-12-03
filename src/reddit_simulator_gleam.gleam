import gleam/erlang/process
import gleam/io
import reddit_simulator_gleam/cli_client
import reddit_simulator_gleam/logger_config
import reddit_simulator_gleam/project_4_initialization
import reddit_simulator_gleam/rest_api_server

pub fn main() {
  // Configure logger to suppress actor warnings
  logger_config.configure_logger()

  // Default: run simulation demo
  // To start the REST API server, use: gleam run -m reddit_simulator_gleam/rest_api_server
  // To run the CLI client, use: gleam run -m reddit_simulator_gleam/cli_client
  io.println("=== Reddit Simulator: Demo Scenario Runner ===")
  io.println("")
  io.println("Note: To start the REST API server, run:")
  io.println("  gleam run -m reddit_simulator_gleam/rest_api_server")
  io.println("")
  io.println("To run the CLI client demo, run:")
  io.println("  gleam run -m reddit_simulator_gleam/cli_client")
  io.println("")
  project_4_initialization.run_demo_simulation()
}
