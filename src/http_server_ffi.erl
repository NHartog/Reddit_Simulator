-module(http_server_ffi).

-export([start/2, stop/1, send_response/2]).

-import(http_bridge_ffi, [send_to_handler/5]).

% Start a simple HTTP server using gen_tcp
% HandlerPid is the Gleam process that will handle requests
-spec start(integer(), pid()) -> {ok, pid()} | {error, term()}.
start(Port, HandlerPid) ->
    Pid = spawn(fun() -> server_loop(Port, HandlerPid) end),
    {ok, Pid}.

% Stop the HTTP server
-spec stop(pid()) -> ok.
stop(Pid) ->
    Pid ! stop,
    ok.

% Send HTTP response
% Response is a tuple: {http_response, Status, HeadersList, Body}
-spec send_response(port(), tuple()) -> ok.
send_response(ClientSocket, {http_response, StatusInt, HeadersList, BodyStr}) ->
    % Convert body string to binary (handle both binary and list)
    BodyBin = case BodyStr of
        B when is_binary(B) -> B;
        L when is_list(L) -> list_to_binary(L);
        _ -> list_to_binary(io_lib:format("~p", [BodyStr]))
    end,
    
    % Convert headers list to map for easier processing
    HeadersMap = maps:from_list(HeadersList),
    
    % Build status line
    StatusLine = <<"HTTP/1.1 ", (integer_to_binary(StatusInt))/binary, " OK\r\n">>,
    
    % Build headers from list
    HeadersBin = lists:foldl(fun({K, V}, Acc) ->
        KBin = case K of
            KStr when is_list(KStr) -> list_to_binary(KStr);
            KB when is_binary(KB) -> KB
        end,
        VBin = case V of
            VStr when is_list(VStr) -> list_to_binary(VStr);
            VB when is_binary(VB) -> VB
        end,
        <<Acc/binary, KBin/binary, ": ", VBin/binary, "\r\n">>
    end, <<>>, HeadersList),
    
    % Add Content-Length if not present
    % Check if Content-Length header exists (headers can be strings or binaries)
    HasContentLength = lists:any(fun({K, _V}) ->
        KLower = case K of
            KStr when is_list(KStr) -> string:lowercase(KStr);
            KBin when is_binary(KBin) -> string:lowercase(binary_to_list(KBin))
        end,
        KLower =:= "content-length"
    end, HeadersList),
    ContentLengthHeader = case HasContentLength of
        false -> <<"Content-Length: ", (integer_to_binary(byte_size(BodyBin)))/binary, "\r\n">>;
        true -> <<>>
    end,
    
    % Build full response
    Response = <<
        StatusLine/binary,
        HeadersBin/binary,
        ContentLengthHeader/binary,
        "\r\n",
        BodyBin/binary
    >>,
    
    gen_tcp:send(ClientSocket, Response),
    gen_tcp:close(ClientSocket),
    ok.

% Server loop
server_loop(Port, HandlerPid) ->
    case gen_tcp:listen(Port, [binary, {active, false}, {reuseaddr, true}]) of
        {ok, ListenSocket} ->
            accept_loop(ListenSocket, HandlerPid);
        Error ->
            Error
    end.

% Accept connections loop
accept_loop(ListenSocket, HandlerPid) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, ClientSocket} ->
            spawn(fun() -> handle_client(ClientSocket, HandlerPid) end),
            accept_loop(ListenSocket, HandlerPid);
        {error, closed} ->
            ok;
        Error ->
            Error
    end.

% Handle client connection
handle_client(ClientSocket, HandlerPid) ->
    try
        case gen_tcp:recv(ClientSocket, 0) of
            {ok, RequestData} ->
                % Debug: show raw request (first 500 chars)
                RawPreview = case byte_size(RequestData) > 500 of
                    true -> binary:part(RequestData, 0, 500);
                    false -> RequestData
                end,
                io:format("DEBUG: Raw request preview: ~s~n", [binary_to_list(RawPreview)]),
                
                % Parse HTTP request
                RequestMap = parse_request(RequestData),
                
                % Check for Expect: 100-continue header
                Headers = maps:get(<<"headers">>, RequestMap, #{}),
                ExpectContinue = maps:get(<<"expect">>, Headers, <<>>),
                ContentLength = maps:get(<<"content-length">>, Headers, <<>>),
                
                % If client expects 100-continue, send it and read body separately
                Body = case ExpectContinue of
                    <<"100-continue">> ->
                        % Send 100 Continue response
                        gen_tcp:send(ClientSocket, <<"HTTP/1.1 100 Continue\r\n\r\n">>),
                        % Read the body based on Content-Length
                        case ContentLength of
                            <<>> ->
                                <<>>;
                            CLBin ->
                                CLStr = binary_to_list(CLBin),
                                case string:to_integer(CLStr) of
                                    {CLInt, _} when CLInt > 0 ->
                                        case gen_tcp:recv(ClientSocket, CLInt) of
                                            {ok, BodyData} -> BodyData;
                                            _ -> <<>>
                                        end;
                                    _ ->
                                        <<>>
                                end
                        end;
                    _ ->
                        % Normal case: body is in the initial request
                        maps:get(<<"body">>, RequestMap, <<>>)
                end,
                
                % Extract method and path
                Method = maps:get(<<"method">>, RequestMap, <<"GET">>),
                Path = maps:get(<<"path">>, RequestMap, <<"/">>),
                
                % Convert to strings for Gleam
                MethodStr = binary_to_list(Method),
                PathStr = binary_to_list(Path),
                BodyStr = binary_to_list(Body),
                
                % Send request to Gleam handler using bridge
                io:format("DEBUG: Sending request to bridge: Method=~s, Path=~s, Body length=~p, Body=~s~n", [MethodStr, PathStr, byte_size(Body), BodyStr]),
                http_bridge_ffi:send_to_handler(HandlerPid, self(), MethodStr, PathStr, BodyStr),
                
                % Wait for response
                io:format("DEBUG: Waiting for response on process ~p~n", [self()]),
                receive
                    {http_response, ResponseStatus, ResponseHeaders, ResponseBody} ->
                        % Response is HttpResponse tuple from Gleam
                        io:format("DEBUG: Received response: Status=~p, Headers=~p, Body type=~p~n", 
                                  [ResponseStatus, length(ResponseHeaders), case ResponseBody of RB when is_binary(RB) -> binary; _ -> list end]),
                        send_response(ClientSocket, {http_response, ResponseStatus, ResponseHeaders, ResponseBody})
                after
                    5000 ->
                        % Timeout - check mailbox for any messages
                        io:format("DEBUG: Request timeout waiting for response on process ~p~n", [self()]),
                        io:format("DEBUG: Checking mailbox for process ~p~n", [self()]),
                        case process_info(self(), messages) of
                            {messages, Msgs} ->
                                io:format("DEBUG: Mailbox contains ~p messages: ~p~n", [length(Msgs), Msgs]);
                            _ ->
                                io:format("DEBUG: Could not get mailbox info~n")
                        end,
                        gen_tcp:send(ClientSocket, <<"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n">>),
                        gen_tcp:close(ClientSocket)
                end;
            {error, _} ->
                gen_tcp:close(ClientSocket)
        end
    catch
        Error:Reason ->
            % Log error and send 500 response
            io:format("Error handling request: ~p:~p~n", [Error, Reason]),
            gen_tcp:send(ClientSocket, <<"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n">>),
            gen_tcp:close(ClientSocket)
    end.

% Parse HTTP request (simplified)
parse_request(RequestData) ->
    try
        % Split request into lines
        Lines = binary:split(RequestData, <<"\r\n">>, [global]),
        
        % Parse request line
        case Lines of
            [RequestLine | HeaderLines] ->
                RequestParts = binary:split(RequestLine, <<" ">>, [global]),
                case RequestParts of
                    [Method, Path | _] ->
                        % Parse headers
                        Headers = parse_headers(HeaderLines),
                        
                        % Find body (after empty line)
                        BodyStart = find_body_start(RequestData),
                        Body = case BodyStart of
                            {ok, Start} ->
                                binary:part(RequestData, Start, byte_size(RequestData) - Start);
                            _ ->
                                <<>>
                        end,
                        
                        #{
                            <<"method">> => Method,
                            <<"path">> => Path,
                            <<"headers">> => Headers,
                            <<"body">> => Body
                        };
                    _ ->
                        % Invalid request line
                        #{
                            <<"method">> => <<"GET">>,
                            <<"path">> => <<"/">>,
                            <<"headers">> => #{},
                            <<"body">> => <<>>
                        }
                end;
            _ ->
                % No request line
                #{
                    <<"method">> => <<"GET">>,
                    <<"path">> => <<"/">>,
                    <<"headers">> => #{},
                    <<"body">> => <<>>
                }
        end
    catch
        _:_ ->
            % Return default on any parse error
            #{
                <<"method">> => <<"GET">>,
                <<"path">> => <<"/">>,
                <<"headers">> => #{},
                <<"body">> => <<>>
            }
    end.

% Parse headers
parse_headers(Lines) ->
    lists:foldl(fun(Line, Acc) ->
        case binary:split(Line, <<": ">>) of
            [Key, Value] ->
                maps:put(string:lowercase(Key), Value, Acc);
            _ ->
                Acc
        end
    end, #{}, Lines).

% Find body start (after \r\n\r\n)
find_body_start(Data) ->
    case binary:match(Data, <<"\r\n\r\n">>) of
        {Pos, _Len} ->
            {ok, Pos + 4};
        nomatch ->
            error
    end.
