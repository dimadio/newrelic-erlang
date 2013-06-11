-module(newrelic_statman).
-compile([export_all]).

poll() ->
    {ok, Metrics} = statman_aggregator:get_window(60),

    Ms = lists:filter(
           fun (M) -> M =/= [] end,
           lists:foldl(fun (M, Acc) ->
                               transform_metric(M) ++ Acc
                       end, [], Metrics)),

    Counters = lists:filter(
                   fun (Metric) ->
                           proplists:get_value(type, Metric) =:= counter andalso
                               (not is_list(proplists:get_value(node, Metric)))
                   end,
                   Metrics),
    Errs = lists:flatmap(
               fun (Metric) ->
                       transform_error_counter(Metric)
               end,
               Counters),

    {[webtransaction_total(Ms), db_total(Ms) | errors_total(Errs) ++ Ms], Errs}.


transform_error_counter(Metric) ->
    case proplists:get_value(key, Metric) of
        {Scope, {error, {Type, Message}}} when is_binary(Scope) ->
            {MegaSecs, Secs, MicroSecs} = os:timestamp(),
            Error = [MegaSecs * 1000000 + Secs + MicroSecs / 1000000,
                     scope2bin(Scope),
                     to_bin(Message),
                     to_bin(Type),
                     {[{<<"parameter_groups">>,{[]}},
                        {<<"stack_trace">>, []},
                        {<<"request_params">>, {[]}},
                        {<<"request_uri">>, Scope}
                      ]}],
            lists:duplicate(proplists:get_value(value, Metric), Error);

        _ ->
            []
    end.


transform_metric(Metric) ->
    transform_metric(Metric, is_list(proplists:get_value(node, Metric))).

transform_metric(_Metric, _Ignore = true) ->
    [];
transform_metric(Metric, _Ignore = false) ->
    case proplists:get_value(type, Metric) of
        histogram ->
            case proplists:get_value(value, Metric) =/= [] of
                true  -> transform_histogram(Metric);
                false -> []
            end;
        counter   -> transform_counter(Metric);
        _         -> []
    end.

transform_counter(Metric) ->
    case proplists:get_value(key, Metric) of
        {Scope, {error, {_Type, _Message}}} when is_binary(Scope) ->
            case proplists:get_value(value, Metric) of
                Errors when Errors > 0 ->
                    [[{[{name, <<"Errors/WebTransaction/Uri", Scope/binary>>},
                        {scope, <<"">>}]},
                      [Errors, 0.0, 0.0, 0.0, 0.0, 0.0]
                     ]];
                _ ->
                    []
            end;
        _ ->
            []
    end.

transform_histogram(Metric) ->
    Summary = statman_histogram:summary(proplists:get_value(value, Metric)),
    Data = [proplists:get_value(observations, Summary),
            proplists:get_value(sum, Summary) / 1000000,
            proplists:get_value(sum, Summary) / 1000000,
            proplists:get_value(min, Summary) / 1000000,
            proplists:get_value(max, Summary) / 1000000,
            proplists:get_value(sum2, Summary) / 1000000000
           ],

    case proplists:get_value(key, Metric) of
        {Scope, {db, Segment}} when is_binary(Scope) ->
            [
             [{[{name, <<"Database", "/", (to_bin(Segment))/binary>>},
                {scope, scope2bin(Scope)}]},
              Data],

             [{[{name, <<"Database/allWeb">>},
                {scope, <<"">>}]},
              Data],

             [{[{name, <<"Database/all">>},
                {scope, <<"">>}]},
              Data]

            ];

        {Scope, {ext, Host}} when is_binary(Scope) andalso is_binary(Host) ->
            [
             [{[{name, <<"External/all">>},
               {scope, <<"">>}]},
             Data],

             [{[{name, <<"External/allWeb">>},
               {scope, <<"">>}]},
             Data],

             [{[{name, <<"External/", Host/binary>>},
               {scope, <<"">>}]},
             Data],

             [{[{name, <<"External/", Host/binary, "/all">>},
               {scope, <<"">>}]},
             Data],

             [{[{name, <<"External/", Host/binary>>},
               {scope, scope2bin(Scope)}]},
              Data]

            ];

        {Scope, {Class, Segment}} when is_binary(Scope) ->
            [[{[{name, <<(class2bin(Class))/binary, "/", (to_bin(Segment))/binary>>},
                {scope, scope2bin(Scope)}]},
              Data]];

        {Scope, total} when is_binary(Scope) ->
            [[{[{name, <<"WebTransaction/Uri", Scope/binary>>},
                {scope, <<"">>}]},
             Data]];

        {A, B} when is_atom(A) andalso is_atom(B) ->
            [[{[{name, <<"OtherTransaction/",
                         (to_bin(A))/binary, "/",
                         (to_bin(B))/binary>>},
                {scope, <<"">>}]},
             Data]];
        _ ->
            []
    end.


webtransaction_total(Ms) ->
    Name = <<"WebTransaction">>,
    N    = lists:sum(pluck(Name, 1, Ms)),
    Sum  = lists:sum(pluck(Name, 2, Ms)),
    Min  = lists:min(pluck(Name, 4, Ms)),
    Max  = lists:max(pluck(Name, 5, Ms)),
    Sum2 = lists:sum(pluck(Name, 6, Ms)),

    [{[{name, <<"HttpDispatcher">>},
       {scope, <<"">>}]},
     [N, Sum, Sum, Min, Max, Sum2]].


db_total(Ms) ->
    Name = <<"Database">>,
    N    = lists:sum(pluck(Name, 1, Ms)),
    Sum  = lists:sum(pluck(Name, 2, Ms)),
    Min  = lists:min(pluck(Name, 4, Ms)),
    Max  = lists:max(pluck(Name, 5, Ms)),
    Sum2 = lists:sum(pluck(Name, 6, Ms)),

    [{[{name, <<"Database/all">>},
       {scope, <<"">>}]},
     [N, Sum, Sum, Min, Max, Sum2]].


errors_total(Errors) ->
    Data = [length(Errors), 0.0, 0.0, 0.0, 0.0, 0.0],
    [[{[{name, <<"Errors/all">>},
        {scope, <<"">>}]},
      Data],
     [{[{name, <<"Errors/allWeb">>},
        {scope, <<"">>}]},
      Data],
     [{[{name, <<"Instance/Reporting">>},
        {scope, <<"">>}]},
      Data]
    ].


pluck(_, _, []) ->
    [0];
pluck(Name, N, L) ->
    lists:map(fun ([_, []]) -> 0;
                  ([{Struct}, D]) ->
                      case binary:match(proplists:get_value(name, Struct), Name) of
                          nomatch ->
                              0;
                          _ ->
                              case proplists:get_value(scope, Struct) =:= <<"">> of
                                  true ->
                                      lists:nth(N, D);
                                  false ->
                                      0
                              end
                      end
              end, L).



class2bin(db) -> <<"Database">>;
class2bin(Atom) when is_atom(Atom) ->
    [F | R] = atom_to_list(Atom),
    list_to_binary([string:to_upper(F) | R]).

to_bin(List) when is_list(List) -> list_to_binary(List);
to_bin(Atom) when is_atom(Atom) -> list_to_binary(atom_to_list(Atom));
to_bin(Number) when is_integer(Number) -> integer_to_list(Number);
to_bin(Bin) when is_binary(Bin)-> Bin.

scope2bin(Url) when is_binary(Url) ->
    <<"WebTransaction/Uri", Url/binary>>.
