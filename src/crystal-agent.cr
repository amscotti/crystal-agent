require "dotenv"
Dotenv.load if File.exists?(".env")

require "anthropic-cr"
require "./crystal_agent/config"
require "./crystal_agent/markdown_renderer"
require "./crystal_agent/tools"
require "./crystal_agent/worker_status"
require "./crystal_agent/worker"
require "./crystal_agent/research"
require "./crystal_agent/supervisor"
require "./crystal_agent/ui"

module CrystalAgent
  VERSION = "0.1.0"

  def self.run
    # Parse command line arguments
    if ARGV.empty? || ARGV.includes?("-h") || ARGV.includes?("--help")
      print_usage
      exit(0)
    end

    query = ARGV.join(" ")

    # Initialize components
    config = Config.new
    Config.validate_environment!
    client = Anthropic::Client.new
    ui = TerminalUI.new
    begin
      supervisor = Supervisor.new(client, config, ui, ui.status_channel)

      # Start UI status listener for real-time updates
      ui.start_status_listener

      # Run research
      result = supervisor.process(query)

      # Render result with styled markdown
      puts MarkdownRenderer.render(result)
    ensure
      ui.shutdown
    end
  rescue ex : ArgumentError
    STDERR.puts "Error: #{ex.message}"
    exit(1)
  rescue ex : Anthropic::AuthenticationError
    STDERR.puts "Error: Invalid API key. Please set ANTHROPIC_API_KEY environment variable."
    exit(1)
  rescue ex : Anthropic::RateLimitError
    STDERR.puts "Error: Rate limit exceeded. Please try again later."
    exit(1)
  rescue ex : Anthropic::APIError
    STDERR.puts "Error: API error - #{ex.message}"
    exit(1)
  rescue ex : Exception
    STDERR.puts "Error: #{ex.message}"
    exit(1)
  end

  private def self.print_usage
    puts <<-USAGE
    Crystal Research Agent v#{VERSION}

    A multi-agent research assistant that uses parallel workers with web search
    to answer complex questions.

    Usage:
      crystal-agent <query>
      crystal-agent "What are the latest developments in quantum computing?"

    Environment Variables:
      ANTHROPIC_API_KEY    - Required. Your Anthropic API key.
      BRAVE_API_KEY        - Required. Your Brave Search API key.
      CRYSTAL_AGENT_MAX_RESEARCH_ROUNDS - Optional. Defaults to 3.

    Examples:
      crystal-agent "What is Crystal programming language?"
      crystal-agent "Compare Rust and Go for systems programming"
      crystal-agent "Latest AI research breakthroughs in 2025"

    USAGE
  end
end

CrystalAgent.run unless PROGRAM_NAME.includes?("crystal-run-spec")
