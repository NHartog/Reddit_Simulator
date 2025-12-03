-module(http_client_ffi).

-export([get/2, post/4, start_httpc/0]).

% Start inets application (required for httpc)
-spec start_httpc() -> {ok, nil} | {error, binary()}.
start_httpc() ->
    case application:start(inets) of
        ok -> {ok, nil};
        {error, {already_started, _}} -> {ok, nil};
        Error -> {error, list_to_binary(io_lib:format("Failed to start inets: ~p", [Error]))}
    end.

% Make HTTP GET request
% Returns: {ok, {StatusCode, HeadersList, BodyString}} | {error, ErrorString}
% Note: Url from Gleam is a binary, need to convert to string
-spec get(binary() | string(), integer()) -> {ok, {integer(), list({string(), string()}), string()}} | {error, string()}.
get(Url, Timeout) ->
    % Convert URL from binary to string if needed
    UrlStr = case Url of
        UB when is_binary(UB) -> binary_to_list(UB);
        US when is_list(US) -> US
    end,
    case httpc:request(get, {UrlStr, []}, [{timeout, Timeout}], [{body_format, binary}]) of
        {ok, {{_, StatusCode, _}, Headers, Body}} ->
            % Convert headers to list of {String, String} tuples
            FormattedHeaders = lists:map(fun({K, V}) ->
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
            % Convert body from binary to string
            BodyStr = case Body of
                B when is_binary(B) -> binary_to_list(B);
                BS when is_list(BS) -> BS
            end,
            {ok, {StatusCode, FormattedHeaders, BodyStr}};
        {error, Reason} ->
            {error, lists:flatten(io_lib:format("HTTP GET failed: ~p", [Reason]))};
        Error ->
            {error, lists:flatten(io_lib:format("HTTP GET error: ~p", [Error]))}
    end.

% Make HTTP POST request
% Returns: {ok, {StatusCode, HeadersList, BodyString}} | {error, ErrorString}
% Note: Url and Body from Gleam are binaries, need to convert to strings
-spec post(binary() | string(), list({binary() | string(), binary() | string()}), binary() | string(), integer()) -> {ok, {integer(), list({string(), string()}), string()}} | {error, string()}.
post(Url, Headers, Body, Timeout) ->
    % Convert URL from binary to string if needed
    UrlStr = case Url of
        UB when is_binary(UB) -> binary_to_list(UB);
        US when is_list(US) -> US
    end,
    % Convert headers from {String, String} to format httpc expects
    FormattedHeaders = lists:map(fun({K, V}) ->
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
    % Convert body to binary (Gleam strings are already binaries)
    BodyBin = case Body of
        B when is_binary(B) -> B;
        L when is_list(L) -> list_to_binary(L)
    end,
    case httpc:request(post, {UrlStr, FormattedHeaders, "application/json", BodyBin}, [{timeout, Timeout}], [{body_format, binary}]) of
        {ok, {{_, StatusCode, _}, ResponseHeaders, ResponseBody}} ->
            % Convert headers to list of {String, String} tuples
            FormattedResponseHeaders = lists:map(fun({K, V}) ->
                KStr = case K of
                    KB when is_binary(KB) -> binary_to_list(KB);
                    KS when is_list(KS) -> KS
                end,
                VStr = case V of
                    VB when is_binary(VB) -> binary_to_list(VB);
                    VS when is_list(VS) -> VS
                end,
                {KStr, VStr}
            end, ResponseHeaders),
            % Convert body from binary to string
            ResponseBodyStr = case ResponseBody of
                RB when is_binary(RB) -> binary_to_list(RB);
                RBS when is_list(RBS) -> RBS
            end,
            {ok, {StatusCode, FormattedResponseHeaders, ResponseBodyStr}};
        {error, Reason} ->
            {error, lists:flatten(io_lib:format("HTTP POST failed: ~p", [Reason]))};
        Error ->
            {error, lists:flatten(io_lib:format("HTTP POST error: ~p", [Error]))}
    end.

