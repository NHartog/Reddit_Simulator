import gleam/int
import gleam/io
import reddit_simulator_gleam/http_bridge
import reddit_simulator_gleam/http_bridge_actor.{create_http_bridge_actor}
import reddit_simulator_gleam/http_server
import reddit_simulator_gleam/master_engine_actor.{create_master_engine_actor}
import reddit_simulator_gleam/rest_api_handler.{create_rest_api_handler}

pub fn start_rest_api_server(port: Int) -> Result(Nil, String) {
  io.println("Starting Reddit Simulator REST API Server...")

  // Create master engine
  case create_master_engine_actor() {
    Ok(master_engine) -> {
      io.println("Master Engine created successfully")

      // Create REST API handler
      case create_rest_api_handler(master_engine) {
        Ok(api_handler) -> {
          io.println("REST API Handler created successfully")

          // Create HTTP bridge actor
          case create_http_bridge_actor(api_handler) {
            Ok(gleam_bridge_subject) -> {
              io.println("HTTP Bridge Actor created successfully")

              // Create Erlang bridge process that forwards messages
              let erlang_bridge_pid =
                http_bridge.start_bridge_process(gleam_bridge_subject)

              // Start HTTP server with Erlang bridge PID
              case http_server.start_server(port, erlang_bridge_pid) {
                Ok(_server_pid) -> {
                  io.println(
                    "HTTP Server started on port " <> int.to_string(port),
                  )
                  io.println("REST API is ready to accept requests!")
                  Ok(Nil)
                }
                Error(msg) -> Error("Failed to start HTTP server: " <> msg)
              }
            }
            Error(msg) -> Error("Failed to create HTTP bridge actor: " <> msg)
          }
        }
        Error(msg) -> Error("Failed to create REST API handler: " <> msg)
      }
    }
    Error(msg) -> Error("Failed to create master engine: " <> msg)
  }
}
