/// Configure Erlang logger to suppress actor warning messages
pub fn configure_logger() {
  // Suppress warnings about actors discarding unexpected messages
  // Set logger level to error to suppress warning level messages
  // This uses logger:set_primary_config(level, error) to set minimum log level to error
  set_logger_level_to_error()
}

// Use Erlang FFI to call logger:set_primary_config(level, error)
// This suppresses warning-level log messages
@external(erlang, "logger_ffi", "set_level_to_error")
fn set_logger_level_to_error() -> Nil
