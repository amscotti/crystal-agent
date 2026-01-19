require "http/client"
require "uri"
require "markout"
require "brave_search"

module CrystalAgent
  # Input struct for fetch_url tool
  struct FetchUrlInput
    include JSON::Serializable

    @[JSON::Field(description: "The URL to fetch content from")]
    getter url : String
  end

  # Input struct for web_search tool
  struct WebSearchInput
    include JSON::Serializable

    @[JSON::Field(description: "The search query to look up")]
    getter query : String

    @[JSON::Field(description: "Number of results to return (default: 10)")]
    getter count : Int32?
  end

  # Tools available to worker agents
  module Tools
    @@brave_client : BraveSearch::Client?

    # Get or create Brave Search client
    private def self.brave_client : BraveSearch::Client
      @@brave_client ||= BraveSearch::Client.new(
        ENV.fetch("BRAVE_API_KEY", "")
      )
    end

    # Create a tool for web searching using Brave Search
    def self.web_search_tool : Anthropic::Tool
      Anthropic.tool(
        name: "web_search",
        description: "Search the web for current information on a topic. Returns relevant search results with titles, URLs, and descriptions.",
        input: WebSearchInput
      ) do |input|
        perform_search(input.query, input.count || 10)
      end
    end

    # Create a tool for fetching and extracting content from URLs
    def self.fetch_url_tool : Anthropic::Tool
      Anthropic.tool(
        name: "fetch_url",
        description: "Fetch and extract the main text content from a URL as markdown. Use this to read articles, documentation, or any web page found during search to get more detailed information.",
        input: FetchUrlInput
      ) do |input|
        fetch_content(input.url)
      end
    end

    # Perform web search using Brave Search API (public for direct access)
    def self.perform_search(query : String, count : Int32) : String
      response = brave_client.web_search(query, count: count)

      results = String.build do |str|
        str << "Search results for: #{query}\n\n"

        web_results = response.web_results
        if web_results.empty?
          str << "No results found.\n"
        else
          web_results.each_with_index do |result, i|
            str << "#{i + 1}. **#{result.title}**\n"
            str << "   URL: #{result.url}\n"
            str << "   #{result.description}\n\n"
          end
        end
      end

      results
    rescue ex : BraveSearch::AuthenticationError
      "Search error: Invalid API key. Please check BRAVE_API_KEY."
    rescue ex : BraveSearch::RateLimitError
      "Search error: Rate limit exceeded. Please try again later."
    rescue ex : Exception
      "Search error: #{ex.message}"
    end

    # Fetch URL content with error handling (public for direct access)
    def self.fetch_content(url : String) : String
      uri = URI.parse(url)

      # Ensure HTTPS
      uri = URI.parse("https://#{url}") unless uri.scheme
      uri = URI.parse(url.sub("http://", "https://")) if uri.scheme == "http"

      client = HTTP::Client.new(uri)
      client.connect_timeout = 10.seconds
      client.read_timeout = 30.seconds

      response = client.get(uri.request_target, headers: HTTP::Headers{
        "User-Agent"      => "CrystalAgent/0.1.0 (Research Assistant)",
        "Accept"          => "text/html,application/xhtml+xml,text/plain",
        "Accept-Language" => "en-US,en;q=0.9",
      })

      if response.success?
        markdown = Markout.convert(response.body)
        "Content from #{uri}:\n\n#{markdown}"
      else
        "Failed to fetch URL: HTTP #{response.status_code}"
      end
    rescue ex : Exception
      "Error fetching URL: #{ex.message}"
    end
  end
end
