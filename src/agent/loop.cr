require "../config/loader"
require "../providers/base"
require "../providers/litellm"
require "../providers/openai"
require "../providers/anthropic"
require "../providers/openrouter"
require "../providers/vllm"
require "./context"
require "./tools/registry"
require "./tools/filesystem"
require "./tools/shell"
require "./tools/web"
require "./tools/memory"
require "../session/manager"
require "../mcp/manager"
require "json"

module Crybot
  module Agent
    # Struct to track individual tool execution
    struct ToolExecution
      property tool_name : String
      property arguments : Hash(String, JSON::Any)
      property result : String

      def initialize(@tool_name : String, @arguments : Hash(String, JSON::Any), @result : String, @success : Bool)
      end

      def success? : Bool
        @success
      end

      def to_h : Hash(String, JSON::Any)
        # Convert arguments hash to JSON::Any format
        args_hash = @arguments.transform_values(&.as_s).transform_values { |v| JSON::Any.new(v) }
        {
          "tool_name" => JSON::Any.new(@tool_name),
          "arguments" => JSON::Any.new(args_hash),
          "result"    => JSON::Any.new(@result),
          "success"   => JSON::Any.new(@success),
        }
      end
    end

    # Struct for agent response with tool execution details
    struct AgentResponse
      property response : String
      property tool_executions : Array(ToolExecution)

      def initialize(@response : String, @tool_executions : Array(ToolExecution) = [] of ToolExecution)
      end

      # For backwards compatibility, allow implicit conversion to string
      def to_s : String
        @response
      end
    end

    class Loop
      @config : Config::ConfigFile
      @provider : Providers::LLMProvider
      @context_builder : ContextBuilder
      @session_manager : Session::Manager
      @max_iterations : Int32
      @mcp_manager : MCP::Manager?

      def initialize(@config : Config::ConfigFile)
        @provider = create_provider
        @context_builder = ContextBuilder.new(@config)
        @session_manager = Session::Manager.instance
        @max_iterations = @config.agents.defaults.max_tool_iterations

        # Register built-in tools
        register_tools

        # Initialize MCP manager
        @mcp_manager = MCP::Manager.new(@config.mcp)
      end

      private def create_provider : Providers::LLMProvider
        model = @config.agents.defaults.model

        # Detect provider from model name prefix
        # Format: provider/model or just model (defaults to zhipu)
        provider_name, actual_model = parse_model_string(model)

        case provider_name
        when "openai", "gpt"
          api_key = @config.providers.openai.api_key
          raise "OpenAI API key not configured" if api_key.empty?
          Providers::OpenAIProvider.new(api_key, actual_model)
        when "anthropic", "claude"
          api_key = @config.providers.anthropic.api_key
          raise "Anthropic API key not configured" if api_key.empty?
          Providers::AnthropicProvider.new(api_key, actual_model)
        when "openrouter"
          api_key = @config.providers.openrouter.api_key
          raise "OpenRouter API key not configured" if api_key.empty?
          Providers::OpenRouterProvider.new(api_key, actual_model)
        when "vllm"
          api_base = @config.providers.vllm.api_base
          raise "vLLM api_base not configured" if api_base.empty?
          Providers::VLLMProvider.new(@config.providers.vllm.api_key, api_base, actual_model)
        else
          # Default to Zhipu
          api_key = @config.providers.zhipu.api_key
          raise "Zhipu API key not configured" if api_key.empty?
          Providers::ZhipuProvider.new(api_key, actual_model)
        end
      end

      private def parse_model_string(model : String) : Tuple(String, String)
        parts = model.split('/', 2)
        if parts.size == 2
          {parts[0], parts[1]}
        else
          # Default provider based on model name patterns
          provider = detect_provider_from_model(model)
          {provider, model}
        end
      end

      private def detect_provider_from_model(model : String) : String
        case model
        when /^gpt-/      then "openai"
        when /^claude-/   then "anthropic"
        when /^glm-/      then "zhipu"
        when /^deepseek-/ then "openrouter"
        when /^qwen-/     then "openrouter"
        else                   "zhipu"
        end
      end

      def process(session_key : String, user_message : String) : AgentResponse
        # Get or create session
        history = @session_manager.get_or_create(session_key)

        # Build messages
        messages = @context_builder.build_messages(user_message, history)

        # Main loop
        iteration = 0
        final_response = ""
        tool_executions = [] of ToolExecution

        while iteration < @max_iterations
          iteration += 1

          # Call LLM
          tools_schemas = Tools::Registry.to_schemas
          response = @provider.chat(messages, tools_schemas, @config.agents.defaults.model)

          # Add assistant message to history
          messages = @context_builder.add_assistant_message(messages, response)

          # Check for tool calls
          calls = response.tool_calls
          if calls && !calls.empty?
            # Execute each tool call
            calls.each do |tool_call|
              result = Tools::Registry.execute(tool_call.name, tool_call.arguments)

              # Track the execution
              execution = ToolExecution.new(
                tool_name: tool_call.name,
                arguments: tool_call.arguments,
                result: result,
                success: !result.starts_with?("Error:")
              )
              tool_executions << execution

              messages = @context_builder.add_tool_result(messages, tool_call, result)
            end

            # Continue loop to get next response with tool results
            next
          end

          # No tool calls, we're done
          final_response = response.content || ""
          break
        end

        if iteration >= @max_iterations
          final_response = "Error: Maximum tool iterations (#{@max_iterations}) exceeded."
        end

        # Save session (only keep last 50 messages to avoid bloating)
        if messages.size > 50
          messages_to_save = messages[-50..-1]
        else
          messages_to_save = messages
        end
        @session_manager.save(session_key, messages_to_save)

        AgentResponse.new(final_response, tool_executions)
      end

      private def register_tools : Nil
        Tools::Registry.register(Tools::ReadFileTool.new)
        Tools::Registry.register(Tools::WriteFileTool.new)
        Tools::Registry.register(Tools::EditFileTool.new)
        Tools::Registry.register(Tools::ListDirTool.new)
        Tools::Registry.register(Tools::ExecTool.new)
        Tools::Registry.register(Tools::WebSearchTool.new)
        Tools::Registry.register(Tools::WebFetchTool.new)

        # Memory tools
        Tools::Registry.register(Tools::SaveMemoryTool.new)
        Tools::Registry.register(Tools::SearchMemoryTool.new)
        Tools::Registry.register(Tools::ListRecentMemoriesTool.new)
        Tools::Registry.register(Tools::RecordMemoryTool.new)
        Tools::Registry.register(Tools::MemoryStatsTool.new)
      end
    end
  end
end
