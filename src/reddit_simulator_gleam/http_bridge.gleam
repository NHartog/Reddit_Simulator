import gleam/erlang/process
import reddit_simulator_gleam/http_bridge_actor.{type HttpBridgeMessage}

// FFI wrapper for http_bridge_ffi:start_bridge_process
@external(erlang, "http_bridge_ffi", "start_bridge_process")
fn start_bridge_process_ffi(
  gleam_bridge_subject: process.Subject(HttpBridgeMessage),
) -> process.Pid

pub fn start_bridge_process(
  gleam_bridge_subject: process.Subject(HttpBridgeMessage),
) -> process.Pid {
  start_bridge_process_ffi(gleam_bridge_subject)
}
