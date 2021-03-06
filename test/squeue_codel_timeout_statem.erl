%%-------------------------------------------------------------------
%%
%% Copyright (c) 2015, James Fish <james@fishcakez.com>
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License. You may obtain
%% a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied. See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%%-------------------------------------------------------------------
-module(squeue_codel_timeout_statem).

-include_lib("proper/include/proper.hrl").

-export([quickcheck/0]).
-export([quickcheck/1]).
-export([check/1]).
-export([check/2]).

-export([module/0]).
-export([args/0]).
-export([init/1]).
-export([handle_timeout/3]).
-export([handle_out/3]).

-export([initial_state/0]).
-export([command/1]).
-export([precondition/2]).
-export([next_state/3]).
-export([postcondition/3]).

-record(state, {codel, timeout}).

quickcheck() ->
    quickcheck([]).

quickcheck(Opts) ->
    proper:quickcheck(prop_squeue(), Opts).

check(CounterExample) ->
    check(CounterExample, []).

check(CounterExample, Opts) ->
    proper:check(prop_squeue(), CounterExample, Opts).

prop_squeue() ->
    ?FORALL(Cmds, commands(?MODULE),
            ?TRAPEXIT(begin
                          {History, State, Result} = run_commands(?MODULE, Cmds),
                          ok,
                          ?WHENFAIL(begin
                                        io:format("History~n~p", [History]),
                                        io:format("State~n~p", [State]),
                                        io:format("Result~n~p", [Result])
                                    end,
                                    aggregate(command_names(Cmds), Result =:= ok))
                      end)).

module() ->
    squeue_codel_timeout.

args() ->
    ?SUCHTHAT({Target, _Interval, Timeout},
              {choose(1, 3), choose(1, 3), choose(1, 4)},
              Timeout > Target).

init({Target, Interval, Timeout}) ->
    #state{codel=squeue_codel_statem:init({Target, Interval}),
           timeout=squeue_timeout_statem:init(Timeout)}.

handle_timeout(Time, L, #state{timeout=Timeout} = State) ->
    %% Must drop at least as many as squeue_timeout to ensure all those
    %% that have timed out have been dropped.
    {MinDrops, NTimeout} = squeue_timeout_statem:handle_timeout(Time, L,
                                                                Timeout),
    handle_timeout(Time, L, State#state{timeout=NTimeout}, MinDrops, 0).

handle_timeout(_Time, _L, State, MinDrops, Drops) when MinDrops =< Drops ->
    {Drops, State};
handle_timeout(Time, L, #state{codel=Codel} = State, MinDrops, Drops) ->
    {Drops2, NCodel} = squeue_codel_statem:handle_out(Time, L, Codel),
    NState = State#state{codel=NCodel},
    {_, NL} = lists:split(Drops2, L),
    case Drops2 of
        0 ->
            handle_timeout(Time, tl(NL), NState, MinDrops, Drops + 1);
        _ ->
            NDrops = Drops2 + Drops,
            handle_timeout(Time, NL, NState, MinDrops, NDrops)
    end.

handle_out(Time, L, #state{codel=Codel} = State) ->
    {Drops, NCodel} = squeue_codel_statem:handle_out(Time, L, Codel),
    {Drops, State#state{codel=NCodel}}.

initial_state() ->
    squeue_statem:initial_state(?MODULE).

command(State) ->
    squeue_statem:command(State).

precondition(State, Call) ->
    squeue_statem:precondition(State, Call).

next_state(State, Value, Call) ->
    squeue_statem:next_state(State, Value, Call).

postcondition(State, Call, Result) ->
    squeue_statem:postcondition(State, Call, Result).
