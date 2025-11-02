-module(logger_ffi).

-export([set_level_to_error/0]).

-spec set_level_to_error() -> ok.
set_level_to_error() ->
    % Set logger primary config level to error to suppress warnings
    logger:set_primary_config(level, error),
    ok.


