require "./spec_helper"

describe CrystalAgent do
  describe CrystalAgent::Config do
    it "creates config with default values" do
      config = CrystalAgent::Config.new
      config.max_tokens.should eq(8192)
      config.model.should eq(Anthropic::Model::CLAUDE_SONNET_4_5)
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
end
