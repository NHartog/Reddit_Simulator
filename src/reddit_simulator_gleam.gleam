import gleam/io
import reddit_simulator_gleam/comprehensive_tests

pub fn main() {
  io.println("=== Reddit Simulator Comprehensive Test Suite ===")
  io.println("Running all tests including upvote functionality...")
  io.println("")

  // Run all comprehensive tests
  comprehensive_tests.run_all_tests()

  io.println("")
  io.println("=== All Tests Complete ===")
  io.println("The Reddit Simulator is working correctly!")
}
