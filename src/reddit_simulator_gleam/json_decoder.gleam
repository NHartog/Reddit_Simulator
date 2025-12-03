import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

// Simple JSON decoding (basic implementation)
// This is a simplified parser - in production you'd use a proper JSON library

pub type JsonValue {
  JsonString(String)
  JsonNumber(Int)
  JsonObject(dict.Dict(String, JsonValue))
  JsonArray(List(JsonValue))
  JsonNull
  JsonBool(Bool)
}

pub fn decode_string_field(
  json: String,
  field: String,
) -> Result(String, String) {
  // Simple extraction: look for "field":"value"
  // Pattern: "field":"value" or "field": "value" (with optional whitespace)
  let pattern = "\"" <> field <> "\":"
  case string.split(json, pattern) {
    [_, rest] -> {
      // Remove leading whitespace
      let rest_trimmed = string.trim(rest)
      // rest_trimmed should start with a quote, then the value, then another quote
      // Example: "test","email":... or "test"}
      // Split on quote to get: ["", "test", ",", ...] or ["", "test", "}", ...]
      case string.split(rest_trimmed, "\"") {
        // Pattern: ["", value, _] where value is between the quotes
        ["", value, _] -> Ok(value)
        // Pattern: [value, _] if there's no leading empty string
        [value, _] -> Ok(value)
        // If we have more elements, try to get the value at index 1
        parts -> {
          // parts should be like ["", "test", ",", ...] or ["", "test", "}", ...]
          // The value is at index 1 (after the empty string before the first quote)
          // Use drop(1) to skip first element, then first() to get the value
          case list.first(list.drop(parts, 1)) {
            Ok(value) -> Ok(value)
            Error(_) ->
              Error(
                "Failed to parse field: "
                <> field
                <> " (rest: "
                <> rest_trimmed
                <> ", parts: "
                <> string.join(parts, "|")
                <> ")",
              )
          }
        }
      }
    }
    _ -> Error("Field not found: " <> field)
  }
}

pub fn decode_int_field(json: String, field: String) -> Result(Int, String) {
  // Simple extraction: look for "field":number
  let pattern = "\"" <> field <> "\":"
  case string.split(json, pattern) {
    [_, rest] -> {
      case string.split(rest, ",") {
        [num_str, _] -> {
          case int.parse(string.trim(num_str)) {
            Ok(num) -> Ok(num)
            Error(_) -> Error("Failed to parse int: " <> num_str)
          }
        }
        [num_str] -> {
          case string.split(num_str, "}") {
            [num_str_clean, _] -> {
              case int.parse(string.trim(num_str_clean)) {
                Ok(num) -> Ok(num)
                Error(_) -> Error("Failed to parse int: " <> num_str_clean)
              }
            }
            _ -> Error("Failed to parse int field: " <> field)
          }
        }
        _ -> Error("Failed to parse int field: " <> field)
      }
    }
    _ -> Error("Field not found: " <> field)
  }
}

pub fn decode_optional_string_field(
  json: String,
  field: String,
) -> Result(option.Option(String), String) {
  // Check if field exists and is not null
  let pattern = "\"" <> field <> "\":"
  case string.split(json, pattern) {
    [_, rest] -> {
      case string.split(rest, ",") {
        [value_part, _] -> {
          case string.split(value_part, "\"") {
            [_, value, _] -> Ok(option.Some(value))
            _ -> {
              // Check if it's null
              case string.contains(value_part, "null") {
                True -> Ok(option.None)
                False -> Error("Failed to parse optional field: " <> field)
              }
            }
          }
        }
        [value_part] -> {
          case string.split(value_part, "\"") {
            [_, value, _] -> Ok(option.Some(value))
            _ -> {
              case string.contains(value_part, "null") {
                True -> Ok(option.None)
                False -> Error("Failed to parse optional field: " <> field)
              }
            }
          }
        }
        _ -> Error("Failed to parse optional field: " <> field)
      }
    }
    _ -> Ok(option.None)
  }
}
