module CrystalAgent
  class Config
    DEFAULT_SUPERVISOR_MODEL      = "claude-sonnet-4-6"
    DEFAULT_WORKER_MODEL          = Anthropic::Model::CLAUDE_HAIKU_4_5
    DEFAULT_MAX_TOKENS            = 8192
    DEFAULT_MAX_RESEARCH_ROUNDS   =    3
    DEFAULT_WORKER_MAX_ITERATIONS =   18
    DEFAULT_SEARCH_COUNT          =   12

    REQUIRED_ENV_VARS = ["ANTHROPIC_API_KEY", "BRAVE_API_KEY"]

    getter model : String
    getter worker_model : String
    getter max_tokens : Int32
    getter max_research_rounds : Int32
    getter worker_max_iterations : Int32
    getter default_search_count : Int32

    def initialize
      @model = string_env("CRYSTAL_AGENT_SUPERVISOR_MODEL", DEFAULT_SUPERVISOR_MODEL)
      @worker_model = string_env("CRYSTAL_AGENT_WORKER_MODEL", DEFAULT_WORKER_MODEL)
      @max_tokens = int_env("CRYSTAL_AGENT_MAX_TOKENS", DEFAULT_MAX_TOKENS, min: 1)
      @max_research_rounds = int_env(
        "CRYSTAL_AGENT_MAX_RESEARCH_ROUNDS",
        DEFAULT_MAX_RESEARCH_ROUNDS,
        min: 1
      )
      @worker_max_iterations = int_env(
        "CRYSTAL_AGENT_WORKER_MAX_ITERATIONS",
        DEFAULT_WORKER_MAX_ITERATIONS,
        min: 1
      )
      @default_search_count = int_env(
        "CRYSTAL_AGENT_DEFAULT_SEARCH_COUNT",
        DEFAULT_SEARCH_COUNT,
        min: 1,
        max: 20
      )
    end

    def self.validate_environment! : Nil
      missing = REQUIRED_ENV_VARS.select do |name|
        value = ENV[name]?
        value.nil? || value.strip.empty?
      end

      return if missing.empty?

      raise ArgumentError.new(
        "Missing required environment variables: #{missing.join(", ")}."
      )
    end

    private def string_env(name : String, default : String) : String
      value = ENV[name]?
      return default if value.nil? || value.strip.empty?

      value
    end

    private def int_env(name : String, default : Int32, *, min : Int32,
                        max : Int32? = nil) : Int32
      value = ENV[name]?
      return default if value.nil? || value.strip.empty?

      parsed = value.to_i?
      raise ArgumentError.new("#{name} must be an integer.") unless parsed
      raise ArgumentError.new("#{name} must be at least #{min}.") if parsed < min

      if max && parsed > max
        raise ArgumentError.new("#{name} must be at most #{max}.")
      end

      parsed
    end
  end
end
