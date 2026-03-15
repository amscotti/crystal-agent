require "set"

module CrystalAgent
  # Callback interface for UI updates
  module UICallback
    abstract def on_start(query : String)
    abstract def on_round_start(round : Int32, topic : String, worker_count : Int32)
    abstract def on_round_complete(round : Int32)
    abstract def on_complete
  end

  # Null callback for when no UI is needed
  class NullUICallback
    include UICallback

    def on_start(query : String); end

    def on_round_start(round : Int32, topic : String, worker_count : Int32); end

    def on_round_complete(round : Int32); end

    def on_complete; end
  end

  # Agentic supervisor that coordinates research using tool_runner
  class Supervisor
    def initialize(@client : Anthropic::Client, @config : Config,
                   @ui_callback : UICallback = NullUICallback.new,
                   @status_channel : Channel(WorkerStatus)? = nil)
      @research_rounds_used = 0
      @seen_aspects = Set(String).new
      @research = Research.new(
        @client,
        @config,
        @status_channel,
        on_round_start: ->(round : Int32, topic : String, count : Int32) {
          @ui_callback.on_round_start(round, topic, count)
          nil
        },
        on_round_complete: ->(round : Int32) {
          @ui_callback.on_round_complete(round)
          nil
        }
      )
    end

    # Process a user query using agentic research
    def process(query : String) : String
      @ui_callback.on_start(query)
      @research_rounds_used = 0
      @seen_aspects.clear

      runner = @client.beta.messages.tool_runner(
        model: @config.model,
        max_tokens: @config.max_tokens,
        system: system_prompt,
        messages: [Anthropic::MessageParam.user(query)],
        tools: [create_research_tool] of Anthropic::Tool,
        max_iterations: @config.max_research_rounds + 4
      )

      runner.each_message { }

      if @research_rounds_used.zero?
        raise "Supervisor returned without performing research."
      end

      answer = runner.final_message.text.strip
      raise "Supervisor returned an empty response." if answer.empty?

      @ui_callback.on_complete
      answer
    end

    private def create_research_tool : Anthropic::Tool
      Anthropic.tool(
        name: "research",
        description: "Conduct research on a topic using multiple parallel workers. Each worker will search the web and read relevant pages to gather information.",
        input: ResearchInput
      ) do |input|
        aspects = sanitize_aspects(input.aspects)
        new_aspects = select_new_aspects(aspects)
        if aspects.empty?
          "Research request invalid. Provide between 1 and 8 non-empty, distinct aspects."
        elsif new_aspects.empty?
          "Research request skipped because it does not add new coverage. Only request follow-up research for genuinely new gaps, contradictions, or missing primary-source validation."
        elsif @research_rounds_used >= @config.max_research_rounds
          "Research limit reached. You have already completed #{@config.max_research_rounds} research rounds. Synthesize the final answer from the findings you already have instead of calling research again."
        else
          @research_rounds_used += 1
          remember_aspects(new_aspects)
          @research.investigate(input.topic, new_aspects)
        end
      end
    end

    private def sanitize_aspects(aspects : Array(String)) : Array(String)
      cleaned = aspects.map(&.strip).reject(&.empty?)
      cleaned.uniq!
      cleaned.size > 8 ? cleaned[0, 8] : cleaned
    end

    private def select_new_aspects(aspects : Array(String)) : Array(String)
      aspects.reject do |aspect|
        @seen_aspects.includes?(normalize_aspect(aspect))
      end
    end

    private def remember_aspects(aspects : Array(String)) : Nil
      aspects.each do |aspect|
        @seen_aspects << normalize_aspect(aspect)
      end
    end

    private def normalize_aspect(aspect : String) : String
      aspect.downcase.gsub(/\s+/, " ").strip
    end

    private def system_prompt : String
      <<-PROMPT
      You are a research supervisor AI. Your job is to thoroughly answer user questions by
      conducting comprehensive research using your research tool.

      You have access to:
      - **research**: Investigate a topic with multiple parallel research workers

      Strategy:
      1. Analyze the user's question to identify the key aspects that need research
      2. Build aspects that widen coverage, not near-duplicates
      3. For current events, releases, products, models, or company claims, ensure at least one aspect targets official or primary sources, and use a `site:` filter when the official domain is obvious
      4. You must use the research tool at least once before answering factual, comparative, or time-sensitive questions
      5. Use the first research round to cover the question broadly
      6. After each round, decide whether there are specific gaps, unresolved contradictions, or missing primary-source confirmation
      7. If needed, do a follow-up research round focused only on the missing information
      8. Stop researching once the answer is well-supported or you reach #{@config.max_research_rounds} total research rounds
      9. Provide a well-organized, thorough final answer

      Final answer rules:
      - Only state claims that are supported by the research tool outputs
      - Prefer primary or official sources when the findings include them
      - If the findings conflict, explicitly describe the conflict instead of overriding it with prior model assumptions
      - Do not claim that something does not exist if the research findings include an official source confirming it
      - Never dismiss a claim as fabricated solely because it is newer than your training cutoff or prior knowledge
      - When an official fetched source conflicts with your prior knowledge, trust the fetched source and explain that it is newer evidence
      - If a claim is only supported by secondary reporting, say that clearly
      - Do not mention your training cutoff, prior knowledge, or inability to independently verify the fetched sources in the final answer
      - Treat fetched pages from official domains returned by the research tool as verified evidence for the purposes of this task

      Guidelines:
      - For most questions, 1 research round with 4-8 good aspects is sufficient
      - Follow-up rounds are allowed when they add NEW information, not repeated coverage
      - NEVER repeat similar queries across rounds - follow-up research must target specific missing facts, conflicts, or validation needs
      - If doing follow-up research, explicitly identify what is missing before calling research again
      - Favor aspect lists that include primary-source validation, technical details, independent confirmation, and practical implications when relevant
      - You may use at most #{@config.max_research_rounds} total research rounds
      - Cite specific sources from the research findings when possible
      PROMPT
    end
  end
end
