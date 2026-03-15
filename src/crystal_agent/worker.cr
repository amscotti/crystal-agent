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
      1. Start with a broad search to map the topic
      2. Run follow-up searches with different phrasings to widen coverage and catch missed angles
      3. For products, models, releases, pricing, docs, or company claims, explicitly search for official sources first, using a `site:` query when the official domain is known
      4. Use freshness filters for current-event or release topics when recency matters
      5. When you find promising URLs, use fetch_url to read the full content, especially for primary sources
      6. Cross-check important claims with multiple sources before treating them as confirmed
      7. Keep searching and reading until you can separate confirmed facts from uncertainty
      8. Synthesize your findings into a clear, well-organized response

      Guidelines:
      - Be thorough - read actual pages, not just snippets
      - Prefer official documentation, vendor blogs, release notes, or product pages when available
      - Treat fetched official pages as higher quality evidence than your prior model knowledge or third-party summaries
      - Never conclude that a product or model does not exist unless you searched for official sources and failed to find confirming evidence
      - Use multiple searches if the first result set looks narrow, noisy, or contradictory
      - Fetch at least 2-4 high-value pages when the topic is substantive
      - Include relevant facts, data, dates, and findings
      - Call out conflicting or uncertain information explicitly instead of guessing
      - If official sources contain information newer than your training knowledge, trust the fetched official source
      - End with short sections titled exactly: Confirmed Findings, Open Questions or Conflicts, and Sources
      PROMPT

      user_message = <<-MSG
      Research Task: #{@task}

      Please research this topic thoroughly. Use web_search to find relevant information,
      then fetch_url to read the full content of important URLs to gather detailed information.
      Use more than one search if needed, prioritize official sources when they exist,
      and clearly separate confirmed information from uncertainty.

      For model, product, or release questions:
      - Start with an official-source search if you can infer the vendor domain
      - Do not treat search snippets alone as confirmed evidence
      - In the final write-up, identify which claims came from official sources
      MSG

      # Create tools with status callbacks
      search_tool = create_search_tool_with_status
      fetch_tool = create_fetch_tool_with_status

      tools = [search_tool, fetch_tool] of Anthropic::Tool
      steps = 0

      runner = @client.beta.messages.tool_runner(
        model: @config.worker_model,
        max_tokens: @config.max_tokens,
        system: system_prompt,
        messages: [Anthropic::MessageParam.user(user_message)],
        tools: tools,
        max_iterations: @config.worker_max_iterations
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
        description: "Search the web for current information on a topic. Use this repeatedly with alternate queries, freshness filters, and offsets to broaden coverage and verify claims.",
        input: WebSearchInput
      ) do |input|
        query_display = input.query.size > 40 ? input.query[0, 37] + "..." : input.query
        emit_status(WorkerAction::Searching, query_display)
        Tools.perform_search(
          input.query,
          input.count || @config.default_search_count,
          offset: input.offset,
          freshness: input.freshness
        )
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
