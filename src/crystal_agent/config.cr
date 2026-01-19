module CrystalAgent
  class Config
    getter model : String = Anthropic::Model::CLAUDE_SONNET_4_5
    getter max_tokens : Int32 = 8192

    def initialize
    end
  end
end
