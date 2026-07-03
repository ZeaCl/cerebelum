# Cerebelum — Workflow Orchestration Engine
# Multi-stage build: deps → build → runtime

FROM hexpm/elixir:1.18.3-erlang-27.3.3-alpine-3.21.3 AS deps

RUN apk add --no-cache build-base git
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

FROM deps AS build
ENV MIX_ENV=prod
COPY config ./config
COPY lib ./lib
COPY priv ./priv
RUN mix deps.compile
RUN mix compile
RUN mix release cerebelum

FROM alpine:3.21.3 AS runtime
RUN apk add --no-cache ncurses-libs openssl libstdc++
WORKDIR /app
COPY --from=build /app/_build/prod/rel/cerebelum ./

ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4001

EXPOSE 4001
EXPOSE 50051

CMD ["/app/bin/cerebelum", "start"]
