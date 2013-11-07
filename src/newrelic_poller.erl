-module(newrelic_poller).
-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {poll_fun}).

%%
%% API
%%

start_link(PollF) ->
    gen_server:start_link(?MODULE, [PollF], []).

%%
%% gen_server callbacks
%%

init([PollF]) ->
    self() ! poll,
    {ok, #state{poll_fun = PollF}}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(poll, State) ->
    erlang:send_after(60000, self(), poll),

    {ok, Hostname} = inet:gethostname(),

    case catch (State#state.poll_fun)() of
        {'EXIT', Error} ->
            error_logger:warning_msg("newrelic_poller: polling failed: ~p~n", [Error]),
            ok;
        {Metrics, Errors} ->
            case catch newrelic:push(Hostname, Metrics, Errors) of
                ok ->
                    ok;
                newrelic_down ->
                    error_logger:warning_msg("newrelic_poller: newrelic is down~n");
                Other ->
                    error_logger:warning_msg("newrelic_poller: push failed: ~p~n",
                                             [Other]),
                    ok
            end
    end,

    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
%% Internal functions
%%
