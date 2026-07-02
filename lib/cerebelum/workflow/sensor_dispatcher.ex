defmodule CerebelumCommunity.Workflows.SensorDispatcher do
  @moduledoc """
  Workflow que orquesta el análisis de eventos del Sensor.

  Pipeline: classify → innovate → store → notify

  Trigger: POST /api/v1/executions
    Body: {"workflow_module": "SensorDispatcher", "inputs": {"event_id": "..."}}
  """

  use Cerebelum.Workflow

  @glia_url "http://glia:4001"
  @sensor_url "http://sensor:4082"
  @kapso_phone_id "597907523413541"
  @kapso_url "https://api.kapso.ai/meta/whatsapp/v24.0"

  workflow do
    timeline do
      fetch_event() |> classify() |> innovate() |> store() |> notify()
    end

    diverge from: classify() do
      {:error, _} -> :skip_analysis
    end

    diverge from: innovate() do
      {:error, _} -> :store_raw
    end

    branch after: classify(), on: result do
      result["classification"] in ["product_requirement", "requirement"] -> :innovate
      true -> :skip_innovate
    end
  end

  # Step 1: Fetch event from Sensor DB
  def fetch_event(context) do
    event_id = Map.get(context.inputs || %{}, "event_id")

    case Req.get("#{@sensor_url}/api/sensor/events/#{event_id}",
           headers: [{"authorization", "Bearer mock_user_123"}]) do
      {:ok, %{status: 200, body: %{"data" => event}}} ->
        text =
          case event["result"] do
            %{"kapso_transcript" => t} when is_binary(t) and t != "" -> t
            %{"text" => t} when is_binary(t) and t != "" -> t
            _ -> ""
          end

        {:ok,
         Map.merge(context, %{
           event: event,
           event_id: event_id,
           transcription: text,
           from_number: get_in(event, ["raw_payload", "message", "from"])
         })}

      {:ok, %{status: s}} ->
        {:error, "Sensor API returned #{s}"}

      {:error, reason} ->
        {:error, "Failed to fetch event: #{inspect(reason)}"}
    end
  end

  # Step 2: Classify via Glia agent
  def classify(context) do
    transcription = Map.get(context, :transcription, "")

    if transcription == "" do
      {:ok, Map.put(context, :classification, "chat_casual")}
    else
      case create_and_message_glia("classifier", classifier_prompt(transcription)) do
        {:ok, response} ->
          classification =
            cond do
              String.contains?(response, "product_requirement") -> "product_requirement"
              String.contains?(response, "question") -> "question"
              String.contains?(response, "urgent") -> "urgent"
              true -> "chat_casual"
            end

          {:ok,
           Map.merge(context, %{
             classification: classification,
             classifier_response: response
           })}

        {:error, reason} ->
          {:error, "Classification failed: #{reason}"}
      end
    end
  end

  # Step 3: Innovacion via Glia agent (solo product_requirement)
  def innovate(context) do
    transcription = Map.get(context, :transcription, "")

    case create_and_message_glia("innovador", innovacion_prompt(transcription)) do
      {:ok, response} ->
        {:ok, Map.put(context, :innovation_result, response)}

      {:error, reason} ->
        {:error, "Innovation analysis failed: #{reason}"}
    end
  end

  # Step 4: Store analysis in Sensor DB
  def store(context) do
    event_id = Map.get(context, :event_id)

    body = %{
      sensor_event_id: event_id,
      analysis_type: Map.get(context, :classification, "unknown"),
      input_text: Map.get(context, :transcription, ""),
      result: %{
        innovation_canvas: Map.get(context, :innovation_result),
        classification: Map.get(context, :classification)
      },
      llm_backend: "glia_deepseek",
      classifier_response: %{raw: Map.get(context, :classifier_response)}
    }

    case Req.post("#{@sensor_url}/api/sensor/analyses",
           json: body,
           headers: [{"authorization", "Bearer mock_user_123"}]) do
      {:ok, %{status: s}} when s in [200, 201] ->
        {:ok, Map.put(context, :stored, true)}

      {:ok, %{status: s, body: body}} ->
        Logger.warning("Store analysis returned #{s}: #{inspect(body)}")
        {:ok, Map.put(context, :stored, true)}

      {:error, reason} ->
        {:error, "Failed to store analysis: #{inspect(reason)}"}
    end
  end

  # Step 5: Notify via Kapso WhatsApp
  def notify(context) do
    from_number = Map.get(context, :from_number)
    classification = Map.get(context, :classification)

    message = notification_message(classification, context)

    if from_number && message != "" do
      kapso_key = System.get_env("KAPSO_API_KEY") || ""

      case Req.post("#{@kapso_url}/#{@kapso_phone_id}/messages",
             json: %{
               messaging_product: "whatsapp",
               to: from_number,
               type: "text",
               text: %{body: message}
             },
             headers: [{"x-api-key", kapso_key}]) do
        {:ok, %{status: s}} when s in [200, 201] ->
          {:ok, Map.put(context, :notified, true)}

        {:ok, %{status: s, body: body}} ->
          Logger.warning("Kapso notification returned #{s}: #{inspect(body)}")
          {:ok, Map.put(context, :notified, false)}

        {:error, reason} ->
          {:error, "Failed to send WhatsApp: #{inspect(reason)}"}
      end
    else
      {:ok, Map.put(context, :notified, false)}
    end
  end

  # Helpers

  defp create_and_message_glia(agent_name, prompt) do
    with {:ok, _} <- create_agent(agent_name),
         {:ok, response} <- message_agent(agent_name, prompt) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_agent(name) do
    case Req.post("#{@glia_url}/api/agents",
           json: %{name: name, skills: []},
           headers: [{"authorization", "Bearer mock_user_123"}]) do
      {:ok, %{status: s}} when s in [200, 201] -> {:ok, name}
      _ -> {:ok, name}
    end
  end

  defp message_agent(name, prompt) do
    case Req.post("#{@glia_url}/api/agents/#{name}/message",
           json: %{text: prompt},
           headers: [{"authorization", "Bearer mock_user_123"}],
           receive_timeout: 120_000,
           timeout: 120_000) do
      {:ok, %{status: 200, body: %{"text" => response}}} ->
        {:ok, response}

      {:ok, %{status: 200, body: body}} ->
        {:ok, inspect(body)}

      {:ok, %{status: s}} ->
        {:error, "Glia returned HTTP #{s}"}

      {:error, reason} ->
        {:error, "Glia unavailable: #{inspect(reason)}"}
    end
  end

  defp classifier_prompt(transcription) do
    """
    Eres un clasificador de contenido de WhatsApp. Lee esta transcripción y clasifícala en UNA de estas categorías:

    - product_requirement: describe un producto/app/solución que quiere construir
    - question: pregunta concreta
    - chat_casual: saludo o conversación informal  
    - urgent: urgencia o queja

    Responde SOLO con la categoría (una palabra).

    Transcripción:
    #{transcription}
    """
  end

  defp innovacion_prompt(transcription) do
    """
    Eres un consultor de innovación y producto. Usando la metodología Value Proposition Design de Osterwalder, analiza esta transcripción y genera:

    1. Customer Jobs (funcionales, sociales, emocionales)
    2. Pains (frecuencia × impacto, priorizados)
    3. Gains (requeridos, esperados, deseados, inesperados)
    4. Value Map (productos/servicios, pain relievers, gain creators)
    5. Propuesta de valor (2-3 líneas, lenguaje del cliente)
    6. Hipótesis principal y supuestos críticos

    Transcripción del cliente:
    #{transcription}
    """
  end

  defp notification_message(classification, context) do
    case classification do
      "product_requirement" ->
        innovation = Map.get(context, :innovation_result, "")

        if innovation != "" do
          "Analicé tu requerimiento. Acá va la propuesta de valor preliminar:\n\n#{String.slice(innovation, 0, 1000)}"
        else
          "Recibí tu requerimiento. Estoy procesándolo y te envío el análisis completo en breve."
        end

      "question" ->
        "Recibí tu consulta. Déjame revisar y te respondo pronto."

      "chat_casual" ->
        ""

      _ ->
        ""
    end
  end
end
