import gleam/io
import reddit_simulator_gleam/test_actors

pub fn main() {
  io.println("=== Reddit Simulator Actor Communication Test ===")
  io.println("Testing if Master and User actors are actually communicating...")
  io.println("")

  // Run the actor communication tests
  test_actors.test_master_engine_actor()

  io.println("")
  io.println("=== Actor Communication Test Complete ===")
  io.println("If you see successful user registrations and retrievals above,")
  io.println("then the Master and User actors are working correctly!")
}
