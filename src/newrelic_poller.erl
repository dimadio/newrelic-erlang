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

    %% {ok, Hostname} = inet:gethostname(),
    AHostname = net_adm:localhost(),
    Internal = ends_with(AHostname, "internal."),
    Hostname = case Internal of
		   true ->
		       lists:reverse(tl(lists:reverse(AHostname)));
		   false ->
		       AHostname
	       end,

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

    {noreply, State};
handle_info(Command, State) ->
    error_logger:warning_msg("newrelic_poller: unrecognized command: ~p~n", [Command]),
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
%% Internal functions
%%
ends_with(String, Suffix)->
    starts_with(lists:reverse(String), lists:reverse(Suffix)).

starts_with([] = _String, []=_Prefix)->
    true;
starts_with( _String, []=_Prefix)->
    true;
starts_with([SH|SR] = _String, [PH|PR]=_Prefix)->
    case SH of
	PH ->
	    starts_with(SR, PR);
	_ -> false
    end.
