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

    @[JSON::Field(description: "Number of results to return between 1 and 20 (default: 12)")]
    getter count : Int32?

    @[JSON::Field(description: "Optional pagination offset between 0 and 9 to inspect additional results")]
    getter offset : Int32?

    @[JSON::Field(description: "Optional freshness filter for current topics: pd, pw, pm, or py")]
    getter freshness : String?
  end

  # Tools available to worker agents
  module Tools
    @@brave_client : BraveSearch::Client?
    @@fetch_cache = {} of String => String
    @@fetch_waiters = {} of String => Array(Channel(String))
    @@fetch_mutex = Mutex.new

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
        description: "Search the web for current information on a topic. Supports broader result counts, pagination offsets, and freshness filters so you can widen or recentre your research.",
        input: WebSearchInput
      ) do |input|
        config = Config.new
        perform_search(
          input.query,
          input.count || config.default_search_count,
          offset: input.offset,
          freshness: input.freshness
        )
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
    def self.perform_search(query : String, count : Int32, *, offset : Int32? = nil,
                            freshness : String? = nil) : String
      response = brave_client.web_search(
        query,
        count: count,
        offset: offset,
        freshness: freshness,
        spellcheck: true,
        extra_snippets: true
      )

      format_search_results(query, response, offset: offset, freshness: freshness)
    rescue ex : BraveSearch::AuthenticationError
      "Search error: Invalid API key. Please check BRAVE_API_KEY."
    rescue ex : BraveSearch::RateLimitError
      "Search error: Rate limit exceeded. Please try again later."
    rescue ex : Exception
      "Search error: #{ex.message}"
    end

    # Fetch URL content with error handling (public for direct access)
    def self.fetch_content(url : String) : String
      uri = normalize_url(url)
      cache_key = uri.to_s
      fetch_state = prepare_fetch(cache_key)

      if cached = fetch_state[:cached]
        return cached
      end

      if waiter = fetch_state[:waiter]
        return waiter.receive
      end

      result = fetch_remote_content(uri)
      complete_fetch(cache_key, result)
      result
    rescue ex : Exception
      "Error fetching URL: #{ex.message}"
    end

    private def self.format_search_results(query : String,
                                           response : BraveSearch::Responses::WebSearch,
                                           *, offset : Int32?, freshness : String?) : String
      String.build do |str|
        append_search_header(str, query, response, freshness)
        append_search_results(str, response.web_results)
        append_pagination_hint(str, response, offset)
      end
    end

    private def self.append_search_header(str : String::Builder, query : String,
                                          response : BraveSearch::Responses::WebSearch,
                                          freshness : String?) : Nil
      str << "Search results for: #{query}\n\n"

      if altered = response.query.altered
        str << "Search engine interpreted this as: #{altered}\n\n"
      end

      return unless freshness

      str << "Freshness filter: #{freshness}\n\n"
    end

    private def self.append_search_results(str : String::Builder,
                                           results : Array(BraveSearch::Responses::WebResult)) : Nil
      if results.empty?
        str << "No results found.\n"
        return
      end

      results.each_with_index do |result, i|
        append_search_result(str, result, i + 1)
      end
    end

    private def self.append_search_result(str : String::Builder,
                                          result : BraveSearch::Responses::WebResult,
                                          index : Int32) : Nil
      str << "#{index}. **#{result.title}**\n"
      str << "   URL: #{result.url}\n"
      append_result_metadata(str, result)
      str << "\n"
    end

    private def self.append_result_metadata(str : String::Builder,
                                            result : BraveSearch::Responses::WebResult) : Nil
      if host = result.meta_url.try(&.hostname)
        str << "   Host: #{host}\n"
      end

      if age = result.age || result.page_age
        str << "   Age: #{age}\n"
      end

      if content_type = result.content_type
        str << "   Type: #{content_type}\n"
      end

      if description = result.description
        str << "   #{description}\n"
      end

      result.extra_snippets.try &.each do |snippet|
        str << "   Extra: #{snippet}\n"
      end
    end

    private def self.append_pagination_hint(str : String::Builder,
                                            response : BraveSearch::Responses::WebSearch,
                                            offset : Int32?) : Nil
      return unless response.has_more_results?

      next_offset = (offset || 0) + 1
      return if next_offset > 9

      str << "More results are available. For a wider search, repeat with offset #{next_offset}.\n"
    end

    private def self.prepare_fetch(cache_key : String) : NamedTuple(cached: String?, waiter: Channel(String)?)
      @@fetch_mutex.synchronize do
        if cached = @@fetch_cache[cache_key]?
          {cached: cached, waiter: nil}
        elsif waiters = @@fetch_waiters[cache_key]?
          waiter = Channel(String).new(1)
          waiters << waiter
          {cached: nil, waiter: waiter}
        else
          @@fetch_waiters[cache_key] = [] of Channel(String)
          {cached: nil, waiter: nil}
        end
      end
    end

    private def self.complete_fetch(cache_key : String, result : String) : Nil
      waiters = [] of Channel(String)

      @@fetch_mutex.synchronize do
        @@fetch_cache[cache_key] = result
        waiters = @@fetch_waiters.delete(cache_key) || [] of Channel(String)
      end

      waiters.each do |waiter|
        waiter.send(result)
        waiter.close
      end
    end

    private def self.normalize_url(url : String) : URI
      uri = URI.parse(url)
      uri = URI.parse("https://#{url}") unless uri.scheme
      uri = URI.parse(url.sub("http://", "https://")) if uri.scheme == "http"
      uri
    end

    private def self.fetch_remote_content(uri : URI) : String
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
