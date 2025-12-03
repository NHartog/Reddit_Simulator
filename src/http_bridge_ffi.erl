-module(http_bridge_ffi).

-export([send_to_handler/5, start_bridge_process/1, get_pid_from_subject/1, send_to_pid/2, send_to_bridge_subject/5]).

% Start a bridge process that receives Erlang messages and forwards to Gleam actor
% GleamBridgeSubject is a {subject, Pid, Ref} tuple
-spec start_bridge_process(tuple()) -> pid().
start_bridge_process(GleamBridgeSubject) ->
    spawn(fun() -> bridge_loop(GleamBridgeSubject) end).

% Bridge process loop
bridge_loop(GleamBridgeSubject) ->
    receive
        {http_request, ReplyPid, Method, Path, Body} ->
            % Convert Erlang strings (lists) to binaries for Gleam
            MethodBin = case Method of
                MB when is_binary(MB) -> MB;
                MS when is_list(MS) -> list_to_binary(MS)
            end,
            PathBin = case Path of
                PB when is_binary(PB) -> PB;
                PS when is_list(PS) -> list_to_binary(PS)
            end,
            BodyBin = case Body of
                BB when is_binary(BB) -> BB;
                BS when is_list(BS) -> list_to_binary(BS)
            end,
            % Send message to Gleam actor through Subject using Gleam's process.send
            % This ensures the message goes through the Subject mechanism
            io:format("DEBUG: Bridge forwarding to Gleam actor Subject ~p: Method=~s, Path=~s~n", [GleamBridgeSubject, Method, Path]),
            % Use Gleam's process.send to send through the Subject
            % The message format is {http_request_from_erlang, ReplyPid, Method, Path, Body}
            gleam@erlang@process:send(GleamBridgeSubject, {http_request_from_erlang, ReplyPid, MethodBin, PathBin, BodyBin}),
            bridge_loop(GleamBridgeSubject);
        stop ->
            ok
    end.

% Send message to Gleam bridge actor Subject using Gleam's process.send
% This function is called from Gleam to send messages through the Subject
-spec send_to_bridge_subject(tuple(), pid(), string(), string(), string()) -> ok.
send_to_bridge_subject(BridgeSubject, ReplyPid, Method, Path, Body) ->
    % Convert Erlang strings (lists) to binaries for Gleam
    MethodBin = case Method of
        MB when is_binary(MB) -> MB;
        MS when is_list(MS) -> list_to_binary(MS)
    end,
    PathBin = case Path of
        PB when is_binary(PB) -> PB;
        PS when is_list(PS) -> list_to_binary(PS)
    end,
    BodyBin = case Body of
        BB when is_binary(BB) -> BB;
        BS when is_list(BS) -> list_to_binary(BS)
    end,
    % Use Gleam's process.send to send through the Subject
    % The message format is {http_request_from_erlang, ReplyPid, Method, Path, Body}
    gleam@erlang@process:send(BridgeSubject, {http_request_from_erlang, ReplyPid, MethodBin, PathBin, BodyBin}),
    ok.

% Send HTTP request to Gleam REST API handler
% HandlerPid is the bridge process PID (Erlang process)
% ReplyPid is the Erlang process waiting for the response
-spec send_to_handler(pid(), pid(), string(), string(), string()) -> ok.
send_to_handler(BridgePid, ReplyPid, Method, Path, Body) ->
    % Send message to bridge process which will forward to Gleam actor
    BridgePid ! {http_request, ReplyPid, Method, Path, Body},
    ok.

% Get Pid from Gleam Subject
% A Gleam Subject is represented as {subject, Pid, Ref} in Erlang
% We need to extract the Pid (element 2)
-spec get_pid_from_subject(tuple()) -> pid().
get_pid_from_subject({subject, Pid, _Ref}) ->
    Pid;
get_pid_from_subject(Pid) when is_pid(Pid) ->
    % If it's already a Pid, return it
    Pid.

% Extract raw Erlang Pid from Gleam process.Pid
% Gleam process.Pid might be wrapped, so we extract the actual Pid
-spec extract_raw_pid(term()) -> pid().
extract_raw_pid(Pid) when is_pid(Pid) ->
    Pid;
extract_raw_pid({pid, Pid}) when is_pid(Pid) ->
    Pid;
extract_raw_pid(Other) ->
    % Try to extract Pid from various formats
    case Other of
        {_, Pid, _} when is_pid(Pid) -> Pid;
        _ -> Other
    end.

% Send HTTP response tuple to Erlang Pid
% Message is {Status, HeadersList, Body}
% Pid might be a Gleam process.Pid, so we extract the raw Erlang Pid
-spec send_to_pid(term(), {integer(), list({string(), string()}), string()}) -> ok.
send_to_pid(PidInput, {Status, Headers, Body}) ->
    % Extract raw Erlang Pid
    RawPid = extract_raw_pid(PidInput),
    % Send as {http_response, Status, Headers, Body} tuple
    BodyLen = case Body of
        B when is_binary(B) -> byte_size(B);
        L when is_list(L) -> length(L);
        _ -> 0
    end,
    io:format("DEBUG: send_to_pid input=~p, extracted=~p (is_pid=~p, is_alive=~p): Status=~p, Headers length=~p, Body length=~p~n", 
              [PidInput, RawPid, is_pid(RawPid), case is_pid(RawPid) of true -> is_process_alive(RawPid); false -> false end, Status, length(Headers), BodyLen]),
    case is_pid(RawPid) andalso is_process_alive(RawPid) of
        true ->
            % Convert headers from binaries to strings for Erlang receive pattern
            HeadersStrings = lists:map(fun({K, V}) ->
                KStr = case K of
                    KB when is_binary(KB) -> binary_to_list(KB);
                    KS when is_list(KS) -> KS
                end,
                VStr = case V of
                    VB when is_binary(VB) -> binary_to_list(VB);
                    VS when is_list(VS) -> VS
                end,
                {KStr, VStr}
            end, Headers),
            % Convert body from binary to string if needed
            BodyStr = case Body of
                BodyBin when is_binary(BodyBin) -> binary_to_list(BodyBin);
                BodyList when is_list(BodyList) -> BodyList
            end,
            Message = {http_response, Status, HeadersStrings, BodyStr},
            io:format("DEBUG: send_to_pid sending message tuple: ~p~n", [Message]),
            RawPid ! Message,
            io:format("DEBUG: send_to_pid message sent successfully to alive process~n"),
            ok;
        false ->
            io:format("DEBUG: ERROR - send_to_pid target process ~p (extracted from ~p) is not a valid alive Pid!~n", [RawPid, PidInput]),
            ok
    end.

