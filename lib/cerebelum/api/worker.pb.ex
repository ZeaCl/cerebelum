defmodule Cerebelum.Worker.V1.ExecuteStepRequest.ResultsEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Cerebelum.Worker.V1.StepResult
end

defmodule Cerebelum.Worker.V1.ExecuteStepRequest.ApproveResponseEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Cerebelum.Worker.V1.ExecuteStepRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :execution_id, 1, type: :string, json_name: "executionId"
  field :step_name, 2, type: :string, json_name: "stepName"
  field :workflow_id, 3, type: :string, json_name: "workflowId"
  field :context, 4, type: Cerebelum.Worker.V1.ExecutionContext

  field :results, 5,
    repeated: true,
    type: Cerebelum.Worker.V1.ExecuteStepRequest.ResultsEntry,
    map: true

  field :approve_response, 6,
    repeated: true,
    type: Cerebelum.Worker.V1.ExecuteStepRequest.ApproveResponseEntry,
    json_name: "approveResponse",
    map: true
end

defmodule Cerebelum.Worker.V1.ExecutionContext.ServicesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Cerebelum.Worker.V1.ExecutionContext do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :auth_token, 1, type: :string, json_name: "authToken"
  field :org_id, 2, type: :string, json_name: "orgId"
  field :user_id, 3, type: :string, json_name: "userId"

  field :services, 4,
    repeated: true,
    type: Cerebelum.Worker.V1.ExecutionContext.ServicesEntry,
    map: true
end

defmodule Cerebelum.Worker.V1.StepResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :status, 1, type: :string
  field :data_json, 2, type: :bytes, json_name: "dataJson"
end

defmodule Cerebelum.Worker.V1.ExecuteStepResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :status, 1, type: :string
  field :result_json, 2, type: :bytes, json_name: "resultJson"
  field :error, 3, type: :string
  field :redirect_to, 4, type: :string, json_name: "redirectTo"
end

defmodule Cerebelum.Worker.V1.HealthCheckRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Cerebelum.Worker.V1.HealthCheckResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :healthy, 1, type: :bool
  field :workflow_ids, 2, repeated: true, type: :string, json_name: "workflowIds"
end

defmodule Cerebelum.Worker.V1.RegisterRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :worker_id, 1, type: :string, json_name: "workerId"
  field :workflows, 2, repeated: true, type: Cerebelum.Worker.V1.WorkflowMetadata
end

defmodule Cerebelum.Worker.V1.WorkflowMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :id, 1, type: :string
  field :label, 2, type: :string
  field :steps, 3, repeated: true, type: Cerebelum.Worker.V1.StepMetadata
end

defmodule Cerebelum.Worker.V1.StepMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :name, 1, type: :string
  field :label, 2, type: :string
  field :hidden, 3, type: :bool
end

defmodule Cerebelum.Worker.V1.RegisterResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :error, 2, type: :string
end
