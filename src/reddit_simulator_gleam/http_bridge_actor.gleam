import gleam/dict
import gleam/erlang/process
import gleam/otp/actor
import reddit_simulator_gleam/rest_api_handler.{type RestApiMessage, HttpRequest}

// Bridge actor that receives Erlang messages and forwards to REST API handler
pub type HttpBridgeMessage {
  HttpRequestFromErlang(
    reply_to: process.Pid,
    method: String,
    path: String,
    body: String,
  )
}

pub type HttpBridgeState {
  HttpBridgeState(rest_api_handler: process.Subject(RestApiMessage))
}

// FFI to send message to Erlang Pid
@external(erlang, "http_bridge_ffi", "send_to_pid")
fn send_to_pid(
  pid: process.Pid,
  message: #(Int, List(#(String, String)), String),
) -> Nil

pub fn create_http_bridge_actor(
  rest_api_handler: process.Subject(RestApiMessage),
) -> Result(process.Subject(HttpBridgeMessage), String) {
  let initial_state = HttpBridgeState(rest_api_handler: rest_api_handler)
  case
    actor.new(initial_state)
    |> actor.on_message(handle_bridge_message)
    |> actor.start()
  {
    Ok(actor_data) -> Ok(actor_data.data)
    Error(err) ->
      Error("Failed to start HttpBridgeActor: " <> error_to_string(err))
  }
}

fn handle_bridge_message(
  state: HttpBridgeState,
  message: HttpBridgeMessage,
) -> actor.Next(HttpBridgeState, HttpBridgeMessage) {
  case message {
    HttpRequestFromErlang(reply_to, method, path, body) -> {
      // Create a reply subject to receive response from REST API handler
      let reply_subject = process.new_subject()

      // Forward request to REST API handler with our reply subject
      let gleam_message = HttpRequest(reply_subject, method, path, body)
      let _ = process.send(state.rest_api_handler, gleam_message)

      // Wait for response and forward to Erlang process
      case process.receive(reply_subject, 5000) {
        Ok(response) -> {
          // Response is HttpResponse, send to Erlang process
          case response {
            rest_api_handler.HttpResponse(status, headers, body_str) -> {
              let headers_list = dict.to_list(headers)
              // Send to Erlang Pid using FFI
              let _ = send_to_pid(reply_to, #(status, headers_list, body_str))
              actor.continue(state)
            }
          }
        }
        Error(_) -> {
          // Timeout - send error to Erlang process
          let _ =
            send_to_pid(reply_to, #(500, [], "{\"error\":\"Request timeout\"}"))
          actor.continue(state)
        }
      }
    }
  }
}

fn error_to_string(err: actor.StartError) -> String {
  case err {
    actor.InitTimeout -> "Initialization timeout"
    actor.InitFailed(message) -> message
    actor.InitExited(_) -> "Actor initialization exited"
  }
}
