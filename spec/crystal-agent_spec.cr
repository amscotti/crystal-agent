require "./spec_helper"

describe CrystalAgent do
  describe CrystalAgent::Config do
    it "creates config with default values" do
      with_env({
        "CRYSTAL_AGENT_SUPERVISOR_MODEL"      => nil,
        "CRYSTAL_AGENT_WORKER_MODEL"          => nil,
        "CRYSTAL_AGENT_MAX_TOKENS"            => nil,
        "CRYSTAL_AGENT_MAX_RESEARCH_ROUNDS"   => nil,
        "CRYSTAL_AGENT_WORKER_MAX_ITERATIONS" => nil,
        "CRYSTAL_AGENT_DEFAULT_SEARCH_COUNT"  => nil,
      }) do
        config = CrystalAgent::Config.new
        config.max_tokens.should eq(8192)
        config.model.should eq("claude-sonnet-4-6")
        config.worker_model.should eq(Anthropic::Model::CLAUDE_HAIKU_4_5)
        config.max_research_rounds.should eq(3)
        config.worker_max_iterations.should eq(18)
        config.default_search_count.should eq(12)
      end
    end

    it "reads config overrides from environment" do
      with_env({
        "CRYSTAL_AGENT_SUPERVISOR_MODEL"      => "claude-opus-4-6",
        "CRYSTAL_AGENT_WORKER_MODEL"          => "claude-sonnet-4-6",
        "CRYSTAL_AGENT_MAX_TOKENS"            => "4096",
        "CRYSTAL_AGENT_MAX_RESEARCH_ROUNDS"   => "5",
        "CRYSTAL_AGENT_WORKER_MAX_ITERATIONS" => "24",
        "CRYSTAL_AGENT_DEFAULT_SEARCH_COUNT"  => "8",
      }) do
        config = CrystalAgent::Config.new
        config.model.should eq("claude-opus-4-6")
        config.worker_model.should eq("claude-sonnet-4-6")
        config.max_tokens.should eq(4096)
        config.max_research_rounds.should eq(5)
        config.worker_max_iterations.should eq(24)
        config.default_search_count.should eq(8)
      end
    end

    it "validates required environment variables" do
      with_env({
        "ANTHROPIC_API_KEY" => nil,
        "BRAVE_API_KEY"     => nil,
      }) do
        expect_raises(ArgumentError, /Missing required environment variables/) do
          CrystalAgent::Config.validate_environment!
        end
      end
    end

    it "rejects invalid numeric configuration" do
      with_env({"CRYSTAL_AGENT_DEFAULT_SEARCH_COUNT" => "99"}) do
        expect_raises(ArgumentError, /CRYSTAL_AGENT_DEFAULT_SEARCH_COUNT must be at most 20/) do
          CrystalAgent::Config.new
        end
      end
    end
  end

  describe CrystalAgent::WorkerResult do
    it "creates a successful result" do
      result = CrystalAgent::WorkerResult.new(
        task_id: 0,
        task: "test task",
        findings: "test findings",
        success: true
      )
      result.success?.should be_true
      result.findings.should eq("test findings")
    end

    it "creates an error result" do
      result = CrystalAgent::WorkerResult.error(0, "test task", "error message")
      result.success?.should be_false
      result.error.should eq("error message")
    end
  end

  describe CrystalAgent::MarkdownRenderer do
    it "renders markdown through glimmer in ascii mode" do
      rendered = CrystalAgent::MarkdownRenderer.render(
        "# Hello\n\n- item",
        width: 60,
        profile: Glimmer::Style::ColorProfile::Ascii
      )

      rendered.should contain("# Hello")
      rendered.should contain("* item")
      rendered.should_not contain("\e[")
    end
  end
end
