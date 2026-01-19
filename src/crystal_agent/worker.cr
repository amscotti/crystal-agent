module CrystalAgent
  # Result from a worker's research task
  struct WorkerResult
    getter task_id : Int32
    getter task : String
    getter findings : String
    getter? success : Bool
    getter error : String?
    getter steps_taken : Int32

    def initialize(@task_id, @task, @findings, @success = true, @error = nil, @steps_taken = 0)
    end

    def self.error(task_id : Int32, task : String, error : String) : WorkerResult
      new(task_id, task, "", false, error, 0)
    end
  end

  # Worker agent that researches a specific topic using web search and URL fetching
  class Worker
    getter id : Int32
    getter task : String
    getter status : Symbol
    getter round : Int32

    MAX_ITERATIONS = 15

    def initialize(@id : Int32, @task : String, @client : Anthropic::Client, @config : Config,
                   @status_channel : Channel(WorkerStatus)? = nil, @round : Int32 = 1)
      @status = :pending
    end

    # Run the research task using tool runner
    def run : WorkerResult
      @status = :running
      emit_status(WorkerAction::Starting, "Initializing research")

      system_prompt = <<-PROMPT
      You are a research assistant focused on a specific task. Your job is to thoroughly
      research the given topic and provide comprehensive, factual findings.

      You have access to these tools:
      1. **web_search** - Search the web for current information on a topic
      2. **fetch_url** - Read the full content of a specific URL for detailed information

      Research Strategy:
      1. Start by searching for relevant information on your topic
      2. When you find promising URLs in search results, use fetch_url to read the full content
      3. Gather information from multiple sources when possible
      4. Continue searching and reading until you have comprehensive information
      5. Synthesize your findings into a clear, well-organized response

      Guidelines:
      - Be thorough - read actual articles, don't just rely on search snippets
      - Cross-reference information from multiple sources
      - Include relevant facts, data, and findings
      - Note the sources of key information
      - Be concise but comprehensive in your final response
      PROMPT

      user_message = <<-MSG
      Research Task: #{@task}

      Please research this topic thoroughly. Use web_search to find relevant information,
      then fetch_url to read the full content of important URLs to gather detailed information.
      Provide comprehensive findings based on your research.
      MSG

      # Create tools with status callbacks
      search_tool = create_search_tool_with_status
      fetch_tool = create_fetch_tool_with_status

      tools = [search_tool, fetch_tool] of Anthropic::Tool
      steps = 0

      runner = @client.beta.messages.tool_runner(
        model: Anthropic::Model::CLAUDE_HAIKU_4_5,
        max_tokens: @config.max_tokens,
        system: system_prompt,
        messages: [Anthropic::MessageParam.user(user_message)],
        tools: tools,
        max_iterations: MAX_ITERATIONS
      )

      # Process through all steps
      runner.each_message do |msg|
        if msg.tool_use?
          steps += 1
          emit_status(WorkerAction::Thinking, "Processing step #{steps}")
        end
      end

      final = runner.final_message
      @status = :completed
      emit_status(WorkerAction::Completed, "Done")
      WorkerResult.new(@id, @task, final.text, true, nil, steps)
    rescue ex : Exception
      @status = :failed
      error_msg = "#{ex.class.name}: #{ex.message || "Unknown error"}"
      emit_status(WorkerAction::Failed, error_msg[0, 50])
      WorkerResult.error(@id, @task, error_msg)
    end

    # Run the worker in a fiber and send result to channel
    def run_async(result_channel : Channel(WorkerResult))
      spawn do
        result = run
        result_channel.send(result)
      end
    end

    private def emit_status(action : WorkerAction, details : String)
      @status_channel.try &.send(WorkerStatus.new(@id, @task, action, details, @round))
    end

    # Create search tool with status updates
    private def create_search_tool_with_status : Anthropic::Tool
      Anthropic.tool(
        name: "web_search",
        description: "Search the web for current information on a topic. Returns relevant search results with titles, URLs, and descriptions.",
        input: WebSearchInput
      ) do |input|
        query_display = input.query.size > 40 ? input.query[0, 37] + "..." : input.query
        emit_status(WorkerAction::Searching, query_display)
        Tools.perform_search(input.query, input.count || 10)
      end
    end

    # Create fetch tool with status updates
    private def create_fetch_tool_with_status : Anthropic::Tool
      Anthropic.tool(
        name: "fetch_url",
        description: "Fetch and extract the main text content from a URL as markdown. Use this to read articles, documentation, or any web page found during search to get more detailed information.",
        input: FetchUrlInput
      ) do |input|
        display_url = input.url.size > 40 ? input.url[0, 37] + "..." : input.url
        emit_status(WorkerAction::Fetching, display_url)
        Tools.fetch_content(input.url)
      end
    end
  end
end
