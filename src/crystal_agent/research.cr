require "json"

module CrystalAgent
  # Input struct for the research tool
  struct ResearchInput
    include JSON::Serializable

    @[JSON::Field(description: "The research topic or question to investigate")]
    getter topic : String

    @[JSON::Field(description: "Specific aspects or sub-questions to explore (1-8 items)")]
    getter aspects : Array(String)
  end

  # Handles research operations - spawns workers and collects findings
  class Research
    def initialize(@client : Anthropic::Client, @config : Config,
                   @status_channel : Channel(WorkerStatus)? = nil,
                   @on_round_start : Proc(Int32, String, Int32, Nil)? = nil,
                   @on_round_complete : Proc(Int32, Nil)? = nil)
      @current_round = 0
    end

    # Perform research on a topic with multiple workers
    def investigate(topic : String, aspects : Array(String)) : String
      @current_round += 1
      round = @current_round

      @on_round_start.try &.call(round, topic, aspects.size)

      result_channel = Channel(WorkerResult).new(aspects.size)

      # Spawn workers for each aspect
      aspects.each_with_index do |aspect, index|
        worker = Worker.new(
          id: index,
          task: aspect,
          client: @client,
          config: @config,
          status_channel: @status_channel,
          round: round
        )
        worker.run_async(result_channel)
      end

      # Collect results
      results = [] of WorkerResult
      aspects.size.times do
        results << result_channel.receive
      end
      result_channel.close

      @on_round_complete.try &.call(round)

      # Format findings
      format_findings(topic, results.sort_by(&.task_id))
    end

    private def format_findings(topic : String, results : Array(WorkerResult)) : String
      String.build do |str|
        str << "# Research Findings: #{topic}\n\n"

        results.each do |result|
          str << "## #{result.task}\n\n"
          if result.success?
            str << result.findings
          else
            str << "*Research failed: #{result.error}*"
          end
          str << "\n\n---\n\n"
        end
      end
    end
  end
end
