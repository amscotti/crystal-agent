require "spec"
require "../src/crystal-agent"

def with_env(overrides : Hash(String, String?), &)
  saved = {} of String => String?

  begin
    overrides.each do |key, value|
      saved[key] = ENV[key]?

      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    saved.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
