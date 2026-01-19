# Crystal Agent

A multi-agent research assistant built in Crystal that uses parallel workers with web search to answer complex questions.

## Demo

[![asciicast](https://asciinema.org/a/769456.svg)](https://asciinema.org/a/769456)

## How It Works

Crystal Agent uses a supervisor-worker architecture with an agentic research loop:

1. **Supervisor Agent**: Analyzes your query and decides what research is needed
2. **Research Tool**: Spawns parallel worker agents to investigate specific aspects
3. **Worker Agents**: Run concurrently using Crystal's fibers, each performing web searches and fetching page content
4. **Review & Iterate**: Supervisor reviews findings and may request additional research if gaps are identified
5. **Synthesis**: All findings are passed to a synthesis call that generates the final answer
6. **Output**: Response is rendered as styled markdown in the terminal

```
┌─────────────────────────────────────────────────────────┐
│                    User Query                           │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Supervisor Agent (Sonnet)                  │
│           Decides what research is needed               │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   Research Tool      │◄──────────────┐
              │   Spawns workers     │               │
              └──────────┬───────────┘               │
                         │                           │
         ┌───────────────┼───────────────┐           │
         │               │               │           │
         ▼               ▼               ▼           │
   ┌───────────┐   ┌───────────┐  ┌───────────┐      │
   │ Worker 1  │   │ Worker 2  │  │ Worker N  │      │
   │  (Haiku)  │   │  (Haiku)  │  │  (Haiku)  │      │
   │ Researcher│   │ Researcher│  │ Researcher│      │
   └─────┬─────┘   └─────┬─────┘  └─────┬─────┘      │
         │               │              │            │
         └───────────────┼──────────────┘            │
                         │                           │
                         ▼                           │
              ┌──────────────────────┐               │
              │  Collect Findings    │               │
              └──────────┬───────────┘               │
                         │                           │
                         ▼                           │
              ┌──────────────────────┐    Yes        │
              │  Gaps in research?   ├───────────────┘
              └──────────┬───────────┘
                         │ No
                         ▼
┌─────────────────────────────────────────────────────────┐
│                 Synthesis (Sonnet)                      │
│          Generates comprehensive answer                 │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│           Styled Markdown Output (Markterm)             │
└─────────────────────────────────────────────────────────┘
```

## Installation

### Prerequisites

- [Crystal](https://crystal-lang.org/) 1.18.2 or later
- An [Anthropic API key](https://console.anthropic.com/)
- A [Brave Search API key](https://brave.com/search/api/)

### Build

```bash
shards install
shards build --release
```

## Usage

```bash
# Set your API keys
export ANTHROPIC_API_KEY="your-anthropic-key"
export BRAVE_API_KEY="your-brave-search-key"

# Run a query
./bin/crystal-agent "What are the latest developments in quantum computing?"
```

You can also create a `.env` file in the project directory:

```
ANTHROPIC_API_KEY=your-anthropic-key
BRAVE_API_KEY=your-brave-search-key
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key (required) |
| `BRAVE_API_KEY` | Your Brave Search API key (required) |

### Examples

```bash
# Simple question
./bin/crystal-agent "What is Crystal programming language?"

# Comparison query
./bin/crystal-agent "Compare Rust and Go for systems programming"

# Current events
./bin/crystal-agent "Latest AI research breakthroughs in 2025"

# Technical deep-dive
./bin/crystal-agent "How does WebAssembly work and what are its use cases?"
```

## Architecture

### Components

- **Config** (`src/crystal_agent/config.cr`): Application configuration
- **Tools** (`src/crystal_agent/tools.cr`): Web search (Brave) and URL fetching tools
- **Worker** (`src/crystal_agent/worker.cr`): Individual research agents that search and fetch content
- **Worker Status** (`src/crystal_agent/worker_status.cr`): Status tracking for worker progress
- **Research** (`src/crystal_agent/research.cr`): Coordinates parallel workers for research tasks
- **Supervisor** (`src/crystal_agent/supervisor.cr`): Agentic coordinator with research tool
- **UI** (`src/crystal_agent/ui.cr`): Terminal progress display with status updates

### Concurrency Model

Crystal Agent uses Crystal's lightweight fibers for true concurrent execution:

- Each worker runs in its own fiber
- Results are collected via channels
- Non-blocking I/O allows efficient parallel web searches

## Development

### Formatting and Linting

```bash
# Format code
crystal tool format src/ spec/

# Run linter
./bin/ameba src/ spec/

# Run tests
crystal spec
```

## Dependencies

- [anthropic-cr](https://github.com/amscotti/anthropic-cr) - Crystal SDK for Anthropic's Claude API
- [brave_search](https://github.com/amscotti/brave_search) - Crystal client for Brave Search API
- [markout](https://github.com/amscotti/markout) - HTML to Markdown conversion
- [markterm](https://github.com/ralsina/markterm) - Terminal markdown rendering
- [dotenv](https://github.com/drum445/dotenv) - Environment variable loading
- [ameba](https://github.com/crystal-ameba/ameba) - Static code analysis (dev)

## License

MIT

## Contributing

1. Fork it (<https://github.com/amscotti/crystal-agent/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Author

- [Anthony Scotti](https://github.com/amscotti)
