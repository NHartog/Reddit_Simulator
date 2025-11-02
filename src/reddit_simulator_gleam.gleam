import gleam/io
import reddit_simulator_gleam/logger_config
import reddit_simulator_gleam/project_4_initialization

pub fn main() {
  // Configure logger to suppress actor warnings
  logger_config.configure_logger()
  io.println("=== Reddit Simulator: Demo Scenario Runner ===")
  project_4_initialization.run_demo_simulation()
}
