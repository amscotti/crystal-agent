require "glimmer"

module CrystalAgent
  module MarkdownRenderer
    DEFAULT_WIDTH = 78
    MIN_WIDTH     = 40

    def self.render(markdown : String, *, width : Int32 = terminal_width,
                    profile : Glimmer::Style::ColorProfile = default_profile) : String
      renderer = Glimmer::Renderer::TermRenderer.new(
        theme: default_theme(profile),
        width: normalize_width(width),
        profile: profile
      )

      renderer.render(markdown)
    end

    def self.default_profile : Glimmer::Style::ColorProfile
      Glimmer::Style::ColorProfile.detect
    end

    def self.terminal_width : Int32
      normalize_width(ENV["COLUMNS"]?.try(&.to_i?) || DEFAULT_WIDTH)
    end

    private def self.default_theme(profile : Glimmer::Style::ColorProfile) : Glimmer::Style::Theme
      profile.ascii? ? Glimmer::Style::Theme.ascii : Glimmer::Style::Theme.dark
    end

    private def self.normalize_width(width : Int32) : Int32
      width < MIN_WIDTH ? MIN_WIDTH : width
    end
  end
end
