import gleam/erlang/process
import gleam/result

// HTTP Server FFI bindings
@external(erlang, "http_server_ffi", "start")
pub fn start_server(
  port: Int,
  handler_pid: process.Pid,
) -> Result(process.Pid, String)

@external(erlang, "http_server_ffi", "stop")
fn stop_server(server_pid: process.Pid) -> Nil
