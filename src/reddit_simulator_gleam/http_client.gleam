import gleam/result

// HTTP Client FFI bindings
@external(erlang, "http_client_ffi", "start_httpc")
pub fn start_httpc() -> Result(Nil, String)

@external(erlang, "http_client_ffi", "get")
pub fn http_get(
  url: String,
  timeout: Int,
) -> Result(#(Int, List(#(String, String)), String), String)

@external(erlang, "http_client_ffi", "post")
pub fn http_post(
  url: String,
  headers: List(#(String, String)),
  body: String,
  timeout: Int,
) -> Result(#(Int, List(#(String, String)), String), String)
