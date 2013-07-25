-module(newrelic).

-export([push/3, push_metric_data/3, push_error_data/3,
         connect/2, get_redirect_host/0]).

% Exported for testing
-export([sample_data/0, sample_error_data/0]).

-define(BASE_URL, "http://~s/agent_listener/invoke_raw_method?").

-define(l2b(L), list_to_binary(L)).
-define(l2i(L), list_to_integer(L)).

%%
%% API
%%

%% @doc: Connects to New Relic and sends the hopefully correctly
%% formatted data and registers it under the given hostname.
push(Hostname, Data, Errors) ->
    Collector = get_redirect_host(),
    RunId = connect(Collector, Hostname),
    case push_metric_data(Collector, RunId, Data) of
        ok ->
            push_error_data(Collector, RunId, Errors);
        Error ->
            Error
    end.


%%
%% NewRelic protocol
%%


get_redirect_host() ->
    Url = url([{method, get_redirect_host}]),
    case request(Url) of
        {ok, {{200, "OK"}, _, Body}} ->
            {ok, {Struct}} = json:decode(Body),
            binary_to_list(proplists:get_value(<<"return_value">>, Struct));
        {ok, {{503, _}, _, _}} ->
            throw(newrelic_down);
        {error, timeout} ->
            throw(newrelic_down)
    end.


connect(Collector, Hostname) ->
    Url = url(Collector, [{method, connect}]),

    Data = [{[
              {agent_version, <<"1.5.0.103">>},
              {app_name, [app_name()]},
              {host, ?l2b(Hostname)},
              {identifier, app_name()},
              {pid, ?l2i(os:getpid())},
              {environment, []},
              {language, <<"python">>},
              {settings, {[]}}
             ]}],

    {ok, JsonData} =json:encode(Data),
    case request(Url, JsonData) of
        {ok, {{200, "OK"}, _, Body}} ->
            {ok, {Struct}} = json:decode(Body),
            {Return} = proplists:get_value(<<"return_value">>, Struct),
            proplists:get_value(<<"agent_run_id">>, Return);
        {ok, {{503, _}, _, _}} ->
            throw(newrelic_down);
        {error, timeout} ->
            throw(newrelic_down)
    end.


push_metric_data(Collector, RunId, MetricData) ->
    Url = url(Collector, [{method, metric_data},
                          {run_id, RunId}]),

    Data = [RunId,
            now_to_seconds() - 60,
            now_to_seconds(),
            MetricData],

    push_data(Url, Data).

push_error_data(Collector, RunId, ErrorData) ->
    Url = url(Collector, [{method, error_data},
                          {run_id, RunId}]),

    Data = [RunId,
            ErrorData],

	push_data(Url, Data).


push_data(Url, Data) ->
    {ok, JsonData} = json:encode(Data),
    case request(Url, JsonData) of
        {ok, {{200, "OK"}, _, Response}} ->
            {ok, {Struct}} = json:decode(Response),
            case proplists:get_value(<<"exception">>, Struct) of
                undefined ->
                    ok;
                Exception ->
                    {error, Exception}
            end;
        {ok, {{503, _}, _, _}} ->
            throw(newrelic_down);
        {error, timeout} ->
            throw(newrelic_down)
    end.


%%
%% HELPERS
%%


now_to_seconds() ->
    {MegaSeconds, Seconds, _} = os:timestamp(),
    MegaSeconds * 1000000 + Seconds.


app_name() ->
    {ok, Name} = application:get_env(newrelic, application_name),
    list_to_binary(Name).


license_key() ->
    {ok, Key} = application:get_env(newrelic, license_key),
    Key.



request(Url) ->
    request(Url, <<"[]">>).

request(Url, Body) ->
    %%lhttpc:request(Url, post, [{"Content-Encoding", "identity"}], Body, 5000).
    {ok, _StatusCode, _RespHeaders, Client} = hackney:request(post, Url, [{"Content-Encoding", "identity"}], Body, []),
    {ok, Body, _Client1} = hackney:body(Client),
    Body.
    


url(Args) ->
    url("collector.newrelic.com", Args).

url(Host, Args) ->
    BaseArgs = [{protocol_version, 10},
                {license_key,  license_key()},
                {marshal_format, json}],
    lists:flatten([io_lib:format(?BASE_URL, [Host]), urljoin(Args ++ BaseArgs)]).

urljoin([H | T]) ->
    [url_var(H) | [["&", url_var(X)] || X <- T]];
urljoin([]) ->
    [].

url_var({Key, Value}) -> [to_list(Key), "=", to_list(Value)].


to_list(Atom) when is_atom(Atom) -> atom_to_list(Atom);
to_list(List) when is_list(List)-> List;
to_list(Int) when is_integer(Int) -> integer_to_list(Int).



sample_data() ->
    [
     [{[{name, <<"MFA/gen_server:call/2">>},
        {scope, <<"WebTransaction/Uri/test">>}]},
      [20,
       2.0030434131622314,
       2.0030434131622314,
       0.10012507438659668,
       0.10023093223571777,
       0.2006091550569522]],

     [{[{name, <<"Database/Redis-HSET">>},
        {scope, <<"WebTransaction/Uri/test">>}]},
      [20,
       2.0030434131622314,
       2.0030434131622314,
       0.10012507438659668,
       0.10023093223571777,
       0.2006091550569522]],

     [{[{name, <<"S3/GET">>},
        {scope, <<"WebTransaction/Uri/test">>}]},
      [20,
       2.0030434131622314,
       2.0030434131622314,
       0.10012507438659668,
       0.10023093223571777,
       0.2006091550569522]],

     [{[{name, <<"WebTransaction">>},
        {scope, <<"">>}]},
      [1,
       2.0055530071258545,
       0.00017213821411132812,
       2.0055530071258545,
       2.0055530071258545,
       4.022242864391558]],

     [{[{name, <<"HttpDispatcher">>},
        {scope, <<"">>}]},
      [1,
       2.0055530071258545,
       0.00017213821411132812,
       2.0055530071258545,
       2.0055530071258545,
       4.022242864391558]],

     [{[{name, <<"Database/allWeb">>},
        {scope, <<"">>}]},
      [1,
       2.0055530071258545,
       0.00017213821411132812,
       2.0055530071258545,
       2.0055530071258545,
       4.022242864391558]],

     [{[{name, <<"Memcache/allWeb">>},
        {scope, <<"">>}]},
      [1,
       2.0055530071258545,
       0.00017213821411132812,
       2.0055530071258545,
       2.0055530071258545,
       4.022242864391558]],

     [{[{name, <<"WebTransaction/Uri/test">>},
        {scope, <<"">>}]},
      [1,
       2.0055530071258545,
       0.00017213821411132812,
       2.0055530071258545,
       2.0055530071258545,
       4.022242864391558]],

     [{[{name, <<"Python/WSGI/Application">>},
        {scope, <<"WebTransaction/Uri/test">>}]},
      [1,
       2.005380868911743,
       7.176399230957031e-05,
       2.005380868911743,
       2.005380868911743,
       4.021552429397218]],

     [{[{name, <<"Instance/Reporting">>},
        {scope, <<"">>}]},
      [1,
       0.0,
       0.0,
       0.0,
       0.0,
       0.0]],


     [{[{name, <<"Errors/WebTransaction/Uri/testUrl">>},
        {scope, <<"">>}]},
      [1,
       0.0,
       0.0,
       0.0,
       0.0,
       0.0]],

     [{[{name, <<"Errors/allWeb">>},
        {scope, <<"">>}]},
      [1,
       0.0,
       0.0,
       0.0,
       0.0,
       0.0]],

     [{[{name, <<"Errors/all">>},
        {scope, <<"">>}]},
      [1,
       0.0,
       0.0,
       0.0,
       0.0,
       0.0]]
    ].

sample_error_data() ->
	[[
	    now_to_seconds(),
	    <<"WebTransaction/Uri/testUrl">>,
	    <<"error">>,
	    <<"RuntimeError">>,
	    {
	        [
	          {<<"parameter_groups">>,
	            {[{<<"Transaction metrics">>,
	                  {[{<<"Thread/Concurrency">>,<<"1.0146">>}]}
	                },
	                {<<"Response properties">>,
	                  {[{<<"CONTENT_LENGTH">>,<<"12">>},
	                      {<<"STATUS">>,<<"200">>}]}
	                }
	              ]}
	          },
	          {<<"stack_trace">>,
	            [
	              <<"Traceback (most recent call last):\n">>,
	              <<"  Stacktrace line 1">>,
	              <<"  Stacktrace line 2">>,
	              <<"  Stacktrace line 3">>,
	              <<"  Stacktrace line 4">>,
	              <<"RuntimeError: error\n">>
	            ]
	          },
	          {<<"request_params">>,{[{<<"key">>,[<<"value">>]}]}},
	          {<<"request_uri">>,<<"/testUrl">>}
	        ]
	     }
	]].

