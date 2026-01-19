require "json"
require "colorize"

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

  # Simple animated dots indicator
  class ThinkingIndicator
    FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    @running : Bool = false
    @message : String

    def initialize(@message : String = "Generating response")
    end

    def start
      @running = true
      spawn do
        frame = 0
        while @running
          print "\r  #{FRAMES[frame].colorize(:cyan)} #{@message}...  "
          STDOUT.flush
          frame = (frame + 1) % FRAMES.size
          sleep 100.milliseconds
        end
      end
      Fiber.yield
    end

    def stop
      @running = false
      Fiber.yield
      print "\r\e[K" # Clear the line
      STDOUT.flush
    end
  end

  # Agentic supervisor that coordinates research using tool_runner
  class Supervisor
    SYSTEM_PROMPT = <<-PROMPT
    You are a research supervisor AI. Your job is to thoroughly answer user questions by
    conducting comprehensive research using your research tool.

    You have access to:
    - **research**: Investigate a topic with multiple parallel research workers

    Strategy:
    1. Analyze the user's question to identify the key aspects that need research
    2. Use the research tool ONCE with well-crafted aspects to cover the question
    3. Review the findings - only do follow-up research if there are SPECIFIC gaps
    4. Provide a well-organized, thorough final answer

    Guidelines:
    - For most questions, ONE research call with 3-8 good aspects is sufficient
    - Only do follow-up research if the first round is clearly missing specific information
    - NEVER repeat similar queries - follow-up research must be for NEW, DIFFERENT aspects
    - If doing follow-up, explicitly identify what's missing before researching
    - Synthesize all findings into a clear, comprehensive response
    - Cite sources when possible
    PROMPT

    SYNTHESIS_PROMPT = <<-PROMPT
    You are a helpful research assistant. Based on the research findings provided,
    give a comprehensive, well-organized answer to the user's question.

    Guidelines:
    - Synthesize information from all research findings
    - Organize your response clearly with sections if appropriate
    - Be thorough but concise
    - Cite sources when possible
    PROMPT

    @collected_findings : Array(String)

    def initialize(@client : Anthropic::Client, @config : Config,
                   @ui_callback : UICallback = NullUICallback.new,
                   @status_channel : Channel(WorkerStatus)? = nil)
      @collected_findings = [] of String
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
      @collected_findings.clear

      research_tool = create_research_tool

      runner = @client.beta.messages.tool_runner(
        model: @config.model,
        max_tokens: @config.max_tokens,
        system: SYSTEM_PROMPT,
        messages: [Anthropic::MessageParam.user(query)],
        tools: [research_tool] of Anthropic::Tool,
        max_iterations: 10
      )

      # Let the tool runner handle all iterations
      runner.each_message { }

      @ui_callback.on_complete

      # Generate final synthesis with thinking indicator
      synthesize_findings(query)
    end

    private def create_research_tool : Anthropic::Tool
      Anthropic.tool(
        name: "research",
        description: "Conduct research on a topic using multiple parallel workers. Each worker will search the web and read relevant pages to gather information.",
        input: ResearchInput
      ) do |input|
        findings = @research.investigate(input.topic, input.aspects)
        @collected_findings << findings
        findings
      end
    end

    private def synthesize_findings(query : String) : String
      findings_text = @collected_findings.join("\n\n")

      user_message = <<-MSG
      Original Question: #{query}

      Research Findings:
      #{findings_text}

      Please provide a comprehensive answer based on these research findings.
      MSG

      indicator = ThinkingIndicator.new("Generating response")
      indicator.start

      response = @client.messages.create(
        model: @config.model,
        max_tokens: @config.max_tokens,
        system: SYNTHESIS_PROMPT,
        messages: [Anthropic::MessageParam.user(user_message)]
      )

      indicator.stop

      response.text
    end
  end
end
