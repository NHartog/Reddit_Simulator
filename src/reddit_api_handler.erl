-module(reddit_api_handler).

-behaviour(elli_handler).

-export([handle/2, handle_event/3]).

% Handle HTTP request
handle(Req, Args) ->
    HandlerPid = Args,
    
    % Extract request information
    Method = elli_request:method(Req),
    Path = elli_request:path(Req),
    Headers = elli_request:headers(Req),
    Body = case elli_request:body(Req) of
        {ok, B} -> B;
        _ -> <<>>
    end,
    
    % Create request map for Gleam
    RequestMap = #{
        <<"method">> => Method,
        <<"path">> => Path,
        <<"headers">> => Headers,
        <<"body">> => Body
    },
    
    % Send request to Gleam handler and wait for response
    HandlerPid ! {http_request, self(), RequestMap},
    receive
        {http_response, ResponseMap} ->
            % Extract response
            Status = maps:get(<<"status">>, ResponseMap, 200),
            ResponseHeaders = maps:get(<<"headers">>, ResponseMap, #{}),
            ResponseBody = maps:get(<<"body">>, ResponseMap, <<>>),
            
            % Convert headers to list of tuples
            HeadersList = maps:to_list(ResponseHeaders),
            
            % Return response
            {Status, HeadersList, ResponseBody}
    after
        5000 ->
            % Timeout
            {500, [], <<"Internal Server Error">>}
    end.

% Handle elli events (not used but required by behaviour)
handle_event(_Event, _Data, _Args) ->
    ok.

