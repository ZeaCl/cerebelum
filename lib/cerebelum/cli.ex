defmodule Cerebelum.CLI do
  require Logger

  @skill_markdown """
  ---
  name: cerebelum
  description: Control deterministic AI agent workflows and executions using the Cerebelum CLI or MCP server.
  allowed-tools:
    - cerebelum
  ---
  # Cerebelum Agent Skill

  This skill allows AI agents to interact with the Cerebelum Workflow Orchestration service, enabling the execution, control, and audit of deterministic agentic workflows.

  ## Prerequisites
  Ensure the `cerebelum` CLI is installed and configured globally. If needed, initialize it by running:
  ```bash
  cerebelum init --url <api_url> --key <api_key>
  ```

  ## Available Commands

  - **List Workflows**: Discover all registered workflows and their timeline steps.
    ```bash
    cerebelum list
    ```
  - **Execute Workflow**: Start a workflow asynchronously.
    ```bash
    cerebelum run <WorkflowModule> [inputs_json]
    ```
    *Example:* `cerebelum run Elixir.Cerebelum.Examples.CounterWorkflow '{"count": 5}'`
  - **Check Status**: Retrieve the current event-sourced reconstructed status and results.
    ```bash
    cerebelum status <execution_id>
    ```
  - **Stop/Cancel Execution**: Cancel a running workflow run.
    ```bash
    cerebelum stop <execution_id>
    ```
  - **Resume Execution**: Resume a paused or hibernated workflow execution.
    ```bash
    cerebelum resume <execution_id>
    ```

  ## MCP Server Integration
  To configure Cerebelum as an MCP server in your agent configuration (e.g., `mcp_config.json`), add:
  ```json
  {
    "mappers": {},
    "mcpServers": {
      "cerebelum": {
        "command": "cerebelum",
        "args": ["mcp"],
        "env": {
          "CEREBELUM_API_URL": "http://localhost:4000"
        }
      }
    }
  }
  ```
  """

  def main(args) do
    # Suppress non-error logs in stdout when running MCP to avoid corrupting JSON-RPC output
    if "mcp" in args do
      Logger.configure(level: :error)
    end

    # Ensure required HTTP client is started
    Application.ensure_all_started(:req)

    # Load configuration
    config = load_config()

    case args do
      ["init" | rest] ->
        init_config(rest)

      ["skills", "list"] ->
        list_skills()

      ["skills", "show"] ->
        show_skill()

      ["skills", "install", dest] ->
        install_skill(dest)

      ["mcp"] ->
        run_mcp(config)

      ["list"] ->
        list_workflows(config)

      ["run", module] ->
        run_workflow(config, module, "{}")

      ["run", module, inputs_str] ->
        run_workflow(config, module, inputs_str)

      ["status", id] ->
        show_status(config, id)

      ["stop", id] ->
        stop_execution(config, id)

      ["resume", id] ->
        resume_execution(config, id)

      _ ->
        print_usage()
    end
  end

  # Config loaders & Initializer

  defp load_config do
    config_dir = Path.expand("~/.config/cerebelum")
    config_file = Path.join(config_dir, "config.json")

    file_config =
      if File.exists?(config_file) do
        case File.read(config_file) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, data} -> data
              _ -> %{}
            end
          _ ->
            %{}
        end
      else
        %{}
      end

    api_url =
      System.get_env("CEREBELUM_API_URL") ||
        Map.get(file_config, "api_url") ||
        "http://localhost:4000"

    api_key =
      System.get_env("CEREBELUM_API_KEY") ||
        Map.get(file_config, "api_key")

    %{
      api_url: String.trim_trailing(api_url, "/"),
      api_key: api_key
    }
  end

  defp init_config(args) do
    config_dir = Path.expand("~/.config/cerebelum")
    File.mkdir_p!(config_dir)
    config_file = Path.join(config_dir, "config.json")

    {opts, _, _} = OptionParser.parse(args, strict: [url: :string, key: :string])

    url = opts[:url]
    key = opts[:key]

    {url, key} =
      if url || key do
        {url || "http://localhost:4000", key}
      else
        IO.puts("Initializing Cerebelum CLI configuration...")
        
        # Interactive prompts
        input_url = IO.gets("Enter Cerebelum API URL [http://localhost:4000]: ") |> String.trim()
        url = if input_url == "", do: "http://localhost:4000", else: input_url

        input_key = IO.gets("Enter Cerebelum API Key (optional): ") |> String.trim()
        key = if input_key == "", do: nil, else: input_key
        {url, key}
      end

    config_data = %{"api_url" => url, "api_key" => key}
    File.write!(config_file, Jason.encode!(config_data, pretty: true))

    IO.puts("Configuration saved to #{config_file}")
    IO.puts("API URL: #{url}")
    if key do
      IO.puts("API Key: [configured]")
    else
      IO.puts("API Key: None")
    end
  end

  # Skills commands

  defp list_skills do
    IO.puts("""
    Available Skills:
    - cerebelum: Control deterministic AI agent workflows and executions using the Cerebelum CLI or MCP server.
    """)
  end

  defp show_skill do
    IO.puts(@skill_markdown)
  end

  defp install_skill(dest_path) do
    skill_dir = Path.join(Path.expand(dest_path), "cerebelum")
    File.mkdir_p!(skill_dir)
    skill_file = Path.join(skill_dir, "SKILL.md")

    File.write!(skill_file, @skill_markdown)
    IO.puts("Skill successfully installed to: #{skill_file}")
  end

  # MCP mode

  def run_mcp(config) do
    loop_mcp(config)
  end

  defp loop_mcp(config) do
    case IO.read(:line) do
      :eof ->
        :ok

      {:error, reason} ->
        Logger.error("Error reading stdin: #{inspect(reason)}")
        :ok

      line ->
        case Jason.decode(line) do
          {:ok, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = req} ->
            handle_request(method, req, id, config)

          {:ok, %{"jsonrpc" => "2.0", "method" => "notifications/" <> _}} ->
            :ok

          _ ->
            send_json_rpc_error(nil, -32700, "Parse error")
        end

        loop_mcp(config)
    end
  end

  defp handle_request("initialize", _req, id, _config) do
    send_response(id, %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{
        "tools" => %{}
      },
      "serverInfo" => %{
        "name" => "cerebelum-mcp",
        "version" => "1.0.0"
      }
    })
  end

  defp handle_request("tools/list", _req, id, _config) do
    tools = [
      %{
        "name" => "list_workflows",
        "description" =>
          "List all available workflows in Cerebelum along with their step structure, timeline steps, branch rules, and version.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "execute_workflow",
        "description" => "Start the asynchronous execution of a registered workflow.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "workflow_module" => %{
              "type" => "string",
              "description" =>
                "The module name of the workflow (e.g., Elixir.Cerebelum.Examples.CounterWorkflow or CounterWorkflow)"
            },
            "inputs" => %{
              "type" => "object",
              "description" => "Map of input key-values for the workflow"
            }
          },
          "required" => ["workflow_module"]
        }
      },
      %{
        "name" => "get_execution_status",
        "description" =>
          "Get the detailed current state of a workflow execution, reconstructed step-by-step from events.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "execution_id" => %{
              "type" => "string",
              "description" => "The UUID of the workflow execution to check"
            }
          },
          "required" => ["execution_id"]
        }
      },
      %{
        "name" => "stop_execution",
        "description" => "Stop/cancel a running workflow execution.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "execution_id" => %{
              "type" => "string",
              "description" => "The UUID of the execution to stop"
            }
          },
          "required" => ["execution_id"]
        }
      },
      %{
        "name" => "resume_execution",
        "description" => "Resume a paused or hibernated workflow execution.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "execution_id" => %{
              "type" => "string",
              "description" => "The UUID of the execution to resume"
            }
          },
          "required" => ["execution_id"]
        }
      }
    ]

    send_response(id, %{"tools" => tools})
  end

  defp handle_request("tools/call", req, id, config) do
    name = get_in(req, ["params", "name"])
    arguments = get_in(req, ["params", "arguments"]) || %{}

    case name do
      "list_workflows" ->
        case call_api(:get, "#{config.api_url}/api/v1/workflows", nil, config.api_key) do
          {:ok, body} ->
            workflows = body["data"] || []
            text = format_workflows_mcp(workflows)
            send_tool_result(id, text)

          {:error, reason} ->
            send_tool_error(id, "Failed to list workflows: #{reason}")
        end

      "execute_workflow" ->
        wf = arguments["workflow_module"]
        inputs = arguments["inputs"] || %{}
        payload = %{"workflow_module" => wf, "inputs" => inputs}

        case call_api(:post, "#{config.api_url}/api/v1/executions", payload, config.api_key) do
          {:ok, body} ->
            exec = body["data"] || %{}

            send_tool_result(
              id,
              "Successfully started execution. ID: #{exec["id"]}, Status: #{exec["status"]}"
            )

          {:error, reason} ->
            send_tool_error(id, "Failed to execute workflow: #{reason}")
        end

      "get_execution_status" ->
        exec_id = arguments["execution_id"]

        case call_api(:get, "#{config.api_url}/api/v1/executions/#{exec_id}", nil, config.api_key) do
          {:ok, body} ->
            exec = body["data"] || %{}
            text = format_execution_mcp(exec)
            send_tool_result(id, text)

          {:error, reason} ->
            send_tool_error(id, "Failed to get execution status: #{reason}")
        end

      "stop_execution" ->
        exec_id = arguments["execution_id"]

        case call_api(:post, "#{config.api_url}/api/v1/executions/#{exec_id}/stop", nil, config.api_key) do
          {:ok, body} ->
            exec = body["data"] || %{}

            send_tool_result(
              id,
              "Successfully stopped execution. ID: #{exec["id"]}, Status: #{exec["status"]}"
            )

          {:error, reason} ->
            send_tool_error(id, "Failed to stop execution: #{reason}")
        end

      "resume_execution" ->
        exec_id = arguments["execution_id"]

        case call_api(:post, "#{config.api_url}/api/v1/executions/#{exec_id}/resume", nil, config.api_key) do
          {:ok, body} ->
            exec = body["data"] || %{}

            send_tool_result(
              id,
              "Successfully resumed execution. ID: #{exec["id"]}, Status: #{exec["status"]}"
            )

          {:error, reason} ->
            send_tool_error(id, "Failed to resume execution: #{reason}")
        end

      _ ->
        send_json_rpc_error(id, -32601, "Method not found")
    end
  end

  defp handle_request(method, _req, id, _config) do
    send_json_rpc_error(id, -32601, "Method not found: #{method}")
  end

  # CLI Handlers

  defp list_workflows(config) do
    case call_api(:get, "#{config.api_url}/api/v1/workflows", nil, config.api_key) do
      {:ok, body} ->
        workflows = body["data"] || []
        IO.puts(format_workflows_mcp(workflows))

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run_workflow(config, module, inputs_str) do
    inputs =
      case Jason.decode(inputs_str) do
        {:ok, decoded} ->
          decoded

        _ ->
          IO.puts(:stderr, "Error: inputs must be a valid JSON string")
          System.halt(1)
      end

    payload = %{"workflow_module" => module, "inputs" => inputs}

    case call_api(:post, "#{config.api_url}/api/v1/executions", payload, config.api_key) do
      {:ok, body} ->
        exec = body["data"] || %{}
        IO.puts("Workflow started successfully!")
        IO.puts("Execution ID: #{exec["id"]}")
        IO.puts("Status: #{exec["status"]}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp show_status(config, id) do
    case call_api(:get, "#{config.api_url}/api/v1/executions/#{id}", nil, config.api_key) do
      {:ok, body} ->
        exec = body["data"] || %{}
        IO.puts(format_execution_mcp(exec))

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp stop_execution(config, id) do
    case call_api(:post, "#{config.api_url}/api/v1/executions/#{id}/stop", nil, config.api_key) do
      {:ok, body} ->
        exec = body["data"] || %{}
        IO.puts("Execution stopped.")
        IO.puts("ID: #{exec["id"]}")
        IO.puts("Status: #{exec["status"]}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp resume_execution(config, id) do
    case call_api(:post, "#{config.api_url}/api/v1/executions/#{id}/resume", nil, config.api_key) do
      {:ok, body} ->
        exec = body["data"] || %{}
        IO.puts("Execution resumed.")
        IO.puts("ID: #{exec["id"]}")
        IO.puts("Status: #{exec["status"]}")

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  # Formatting helpers

  defp format_workflows_mcp(workflows) do
    if Enum.empty?(workflows) do
      "No workflows registered in Cerebelum."
    else
      lines = [
        "Available Workflows:",
        "===================="
      ]

      wf_lines =
        Enum.map(workflows, fn wf ->
          """
          - Module: #{wf["module"]}
            Version: #{wf["version"]}
            Timeline: #{Enum.join(wf["timeline"], " -> ")}
            Diverges: #{inspect(wf["diverges"])}
            Branches: #{inspect(wf["branches"])}
          """
        end)

      Enum.join(lines ++ wf_lines, "\n")
    end
  end

  defp format_execution_mcp(exec) do
    """
    Execution Details:
    ------------------
    ID: #{exec["id"]}
    Workflow Module: #{exec["workflow_module"]}
    Status: #{exec["status"]}
    Current Step: #{exec["current_step"] || "None"} (Index: #{exec["current_step_index"]})
    Timeline Progress: #{exec["timeline_progress"]}
    Iteration: #{exec["iteration"]}
    Events Applied: #{exec["events_applied"]}
    Started At: #{exec["started_at"]}
    Completed At: #{exec["completed_at"] || "N/A"}
    Duration: #{if exec["duration_ms"], do: "#{exec["duration_ms"]} ms", else: "N/A"}

    Results:
    #{Jason.encode!(exec["results"] || %{}, pretty: true)}

    Error:
    #{if exec["error"], do: Jason.encode!(exec["error"], pretty: true), else: "None"}
    """
  end

  # HTTP Request helper

  defp call_api(method, url, payload, api_key) do
    headers = [
      {"content-type", "application/json"}
    ]

    headers =
      if api_key && api_key != "" do
        [{"authorization", "Bearer #{api_key}"} | headers]
      else
        headers
      end

    opts = [
      method: method,
      url: url,
      headers: headers,
      retry: false
    ]

    opts = if payload, do: [{:body, Jason.encode!(payload)} | opts], else: opts

    case Req.request(opts) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        {:ok, response.body}

      {:ok, %{status: status, body: body}} ->
        error_msg =
          if is_map(body), do: body["error"] || "Status #{status}", else: "Status #{status}"

        {:error, error_msg}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  # JSON-RPC Send helpers

  defp send_response(id, result) do
    resp = %{
      "jsonrpc" => "2.0",
      "result" => result,
      "id" => id
    }

    IO.puts(Jason.encode!(resp))
  end

  defp send_tool_result(id, text) do
    send_response(id, %{
      "content" => [
        %{
          "type" => "text",
          "text" => text
        }
      ]
    })
  end

  defp send_tool_error(id, error_message) do
    resp = %{
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => -32000,
        "message" => error_message
      },
      "id" => id
    }

    IO.puts(Jason.encode!(resp))
  end

  defp send_json_rpc_error(id, code, message) do
    resp = %{
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => code,
        "message" => message
      },
      "id" => id
    }

    IO.puts(Jason.encode!(resp))
  end

  defp print_usage do
    IO.puts("""
    Cerebelum CLI & MCP Server

    Usage:
      cerebelum list                          List all available workflows
      cerebelum run <module> [inputs_json]    Start workflow execution
      cerebelum status <execution_id>         Get execution details
      cerebelum stop <execution_id>           Stop running execution
      cerebelum resume <execution_id>         Resume paused/hibernated execution
      cerebelum mcp                           Run as MCP server (stdio transport)
      cerebelum init [--url URL] [--key KEY]  Initialize CLI configuration (interactive or flags)
      cerebelum skills list                   List available skills
      cerebelum skills show                   Show Cerebelum skill details
      cerebelum skills install <dest_path>    Install skill folder to target path

    Environment Variables:
      CEREBELUM_API_URL                       API server URL (default: http://localhost:4000)
      CEREBELUM_API_KEY                       API authorization key (optional)
    """)
  end
end
