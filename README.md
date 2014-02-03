# Project forked and tuned up  a bit
* http client replaced with hackney
* json replaced with jiffy
* throw replaced with logging
* background task support added

# NewRelic for Erlang

This library implements the New Relic API and allows sending arbitrary
metrics directly to their collectors from Erlang. [New
Relic](http://newrelic.com/) is a paid "application monitoring"
service.

You need to supply the metrics on the correct format. If you happen to
be using [statman](https://github.com/knutin/statman) you can use the
included `newrelic_statman` transformer. It is fairly easy to
transform the metrics, so if you're using Folsom, estatsd or your own
tools, have a look at `newrelic_statman` to see how it's done.

A sample application showing how to use this application is available [here](https://github.com/dparnell/newrelic-erlang-example).

## Configuration

Two application environment variables must be set in the `newrelic` app:

 * `application_name`: human readable name of the app, will show up in the web interface
 * `license_key`: secret license key

Start newrelic poller as following:

    case application:get_env(newrelic,license_key) of
	undefined ->
	    ok;
	_ ->
	    my_supervisor:add_child(newrelic_poller, [fun newrelic_statman:poll/0], worker)
    end,

 Having inside the "my_supervisor" 
 

    -define(CHILD(I, Params, Type), {I, {I, start_link, Params}, permanent, 5000, Type, [I]}).
    add_child(Module, Params, Type)->
        supervisor:start_child(?MODULE, ?CHILD(Module, Params, Type)).

## Statman integration

If you're using Statman and use the following conventions for naming
your keys, you can use New Relic "for free".

To record web transaction:

    statman_histogram:record_value({<<"/URL">>, total}, StartProcess)

 * URL have to start with "/"
 * StartProcess is result of os:timestamp() at executiom start


To record web transaction break down:

    statman_histogram:record_value({<<"/URL">>, 
                                    {'OtherTransaction/Python', FuncName}}, Start)
				    
  * FuncName is atom, function name
  

To record error:

    statman_counter:incr({<<"/URL">>, {error,
    					      {"ErrorCode", <<"Message">>}}})

Other:
  * `{<<"/hello/world">>, {class, segment}}` - Web transaction, class 
   better to be 'OtherTransaction/Python' and segment to be atom - function name
   so calls will show up in the "Performance
   breakdown"
 * {<</task/name>>, {task, <<"upload_raw">>}}, StartTime) - Record background task, will show up in background tasks tab
 * `{<<"/hello/world">>, {db, <<"something">>}}` - Web transaction
   with database access, will show up in the "Performance breakdown"
   as well as "Overview". Unfortunately not in "Database" yet
 * `{<<"/hello/world">>, total}` - Total time of the transaction,
   inclusive any children. Will show up in the "Overview"
 * `{<<"/hello/world">>, {ext, <<"some.host.name">>}}` - External call
   inside a web transaction, will show up in the "Performance
   breakdown" and "External services"
 * `{foo, bar}` - Background task
 * `{<<"/hello/world">>, {error, {type, message}}}` - Error, counters with keys
   like this will show up in under "Errors"

