defmodule Cerebelum.WorkerRegistry do
  @moduledoc """
  Registry of Python workers and their workflows.

  Stores workflow metadata received via gRPC Register calls
  and exposes it to the REST API.
  """
  use GenServer

  # ── Client API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def register_workflows(worker_id, workflows) do
    GenServer.call(__MODULE__, {:register, worker_id, workflows})
  end

  def register_worker(worker_id, url, workflows) do
    GenServer.call(__MODULE__, {:register_worker, worker_id, url, workflows})
  end

  def unregister_worker(worker_id) do
    GenServer.call(__MODULE__, {:unregister, worker_id})
  end

  def list_all do
    GenServer.call(__MODULE__, :list)
  end

  def list_workers do
    GenServer.call(__MODULE__, :list_workers)
  end

  def get_worker(worker_id) do
    GenServer.call(__MODULE__, {:get_worker, worker_id})
  end

  def get_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:get, workflow_id})
  end

  def find_worker_for_workflow(workflow_id) do
    GenServer.call(__MODULE__, {:find_worker, workflow_id})
  end

  # ── Server Callbacks ──

  @impl true
  def init(_) do
    {:ok, %{workers: %{}, worker_urls: %{}, workflows: %{}}}
  end

  @impl true
  def handle_call({:register_worker, worker_id, url, workflows}, _from, state) do
    workflows_map = Map.new(workflows, fn wf -> {wf["id"], wf} end)

    new_state = %{
      state
      | workers: Map.put(state.workers, worker_id, workflows_map),
        worker_urls: Map.put(state.worker_urls, worker_id, url),
        workflows: Map.merge(state.workflows, workflows_map)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:register, worker_id, workflows}, _from, state) do
    workflows_map = Map.new(workflows, fn wf -> {wf["id"], wf} end)

    new_state = %{
      state
      | workers: Map.put(state.workers, worker_id, workflows_map),
        workflows: Map.merge(state.workflows, workflows_map)
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister, worker_id}, _from, state) do
    {removed, workers} = Map.pop(state.workers, worker_id)

    new_workflows =
      if removed do
        removed_ids = Map.keys(removed)
        Map.drop(state.workflows, removed_ids)
      else
        state.workflows
      end

    {:reply, :ok, %{state | workers: workers, workflows: new_workflows}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.workflows), state}
  end

  @impl true
  def handle_call({:get, workflow_id}, _from, state) do
    {:reply, Map.get(state.workflows, workflow_id), state}
  end

  @impl true
  def handle_call(:list_workers, _from, state) do
    workers =
      Enum.map(state.worker_urls, fn {id, url} ->
        wf_count = state.workers[id] |> Map.keys() |> length()
        %{id: id, url: url, workflow_count: wf_count}
      end)

    {:reply, workers, state}
  end

  @impl true
  def handle_call({:get_worker, worker_id}, _from, state) do
    {:reply, Map.get(state.worker_urls, worker_id), state}
  end

  @impl true
  def handle_call({:find_worker, workflow_id}, _from, state) do
    worker =
      Enum.find(state.workers, fn {_wid, wfs} ->
        Map.has_key?(wfs, workflow_id)
      end)

    case worker do
      {wid, _wfs} -> {:reply, {:ok, wid, state.worker_urls[wid]}, state}
      nil -> {:reply, {:error, :not_found}, state}
    end
  end
end
