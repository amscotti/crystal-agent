require "colorize"

module CrystalAgent
  # Terminal UI for displaying research progress with live updates
  class TerminalUI
    include UICallback

    ACTION_ICONS = {
      WorkerAction::Starting  => "◐",
      WorkerAction::Searching => "🔍",
      WorkerAction::Fetching  => "📄",
      WorkerAction::Thinking  => "💭",
      WorkerAction::Completed => "✓",
      WorkerAction::Failed    => "✗",
    }

    SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    @status_channel : Channel(WorkerStatus)?
    @ui_fiber : Fiber?
    @running : Bool
    @current_round : Int32
    @rounds : Hash(Int32, RoundDisplay)
    @thinking : Bool
    @thinking_fiber : Fiber?

    def initialize
      @running = false
      @current_round = 0
      @rounds = {} of Int32 => RoundDisplay
      @thinking = false
    end

    def status_channel : Channel(WorkerStatus)
      @status_channel ||= Channel(WorkerStatus).new(100)
    end

    # UICallback implementation
    def on_start(query : String)
      print_header
      puts "  #{"▶".colorize(:yellow)} Researching: #{truncate(query, 60)}"
      puts
    end

    def on_round_start(round : Int32, topic : String, worker_count : Int32)
      stop_thinking_indicator
      @current_round = round
      @rounds[round] = RoundDisplay.new(round, topic, worker_count)

      puts "  #{"Round #{round}:".colorize(:cyan)} #{truncate(topic, 50)}"

      # Print initial worker lines
      worker_count.times do |i|
        puts "    #{ACTION_ICONS[WorkerAction::Starting].colorize(:yellow)} W#{i + 1} waiting..."
      end
    end

    def on_round_complete(round : Int32)
      if rd = @rounds[round]?
        rd.completed = true
      end
      puts
      start_thinking_indicator("Processing results")
    end

    def on_complete
      stop_thinking_indicator
      puts "  #{"✓".colorize(:green)} Research complete"
      puts
      puts "━━━ Results ━━━".colorize(:green).bold
      puts
    end

    private def start_thinking_indicator(message : String)
      @thinking = true
      @thinking_fiber = spawn do
        frame = 0
        while @thinking
          print "\r  #{SPINNER_FRAMES[frame].colorize(:cyan)} #{message}...  "
          STDOUT.flush
          frame = (frame + 1) % SPINNER_FRAMES.size
          sleep 100.milliseconds
        end
      end
      Fiber.yield
    end

    private def stop_thinking_indicator
      return unless @thinking
      @thinking = false
      Fiber.yield
      print "\r\e[K" # Clear the line
      STDOUT.flush
    end

    # Start listening for worker status updates
    def start_status_listener
      @running = true
      @ui_fiber = spawn do
        while @running
          select
          when status = status_channel.receive
            update_worker_display(status)
          when timeout(50.milliseconds)
            # Keep fiber alive
          end
        end
      end
    end

    # Stop the status listener
    def stop_status_listener
      return unless @running

      @running = false
      Fiber.yield
      @ui_fiber = nil
    end

    def shutdown
      stop_thinking_indicator
      stop_status_listener
    end

    private def print_header
      puts
      puts "╔═══════════════════════════════════════╗".colorize(:blue).bold
      puts "║       Crystal Research Agent          ║".colorize(:blue).bold
      puts "╚═══════════════════════════════════════╝".colorize(:blue).bold
      puts
    end

    private def update_worker_display(status : WorkerStatus)
      round = status.round
      return unless rd = @rounds[round]?
      return if rd.completed?

      worker_id = status.worker_id
      lines_up = rd.worker_count - worker_id

      # Move cursor up, clear line, print new status, move back down
      print "\e[#{lines_up}A" # Move up
      print "\e[K"            # Clear line
      print_worker_status(status)
      print "\e[#{lines_up}B" # Move back down
      print "\r"

      STDOUT.flush
    end

    private def print_worker_status(status : WorkerStatus)
      icon = ACTION_ICONS[status.action]
      task = truncate(status.task, 30)

      color = case status.action
              when .searching? then :cyan
              when .fetching?  then :magenta
              when .thinking?  then :yellow
              when .completed? then :green
              when .failed?    then :red
              else                  :yellow
              end

      detail = case status.action
               when .searching?
                 "searching...".colorize(:cyan)
               when .fetching?
                 "fetching #{truncate(status.details, 25)}".colorize(:magenta)
               when .thinking?
                 "thinking...".colorize(:yellow)
               when .completed?
                 status.details.colorize(:green)
               when .failed?
                 status.details.colorize(:red)
               else
                 "starting...".colorize(:yellow)
               end

      print "    #{icon.colorize(color)} #{"W#{status.worker_id + 1}".colorize.bold} #{task} #{detail}"
    end

    private def truncate(str : String, max : Int32) : String
      str.size > max ? str[0, max - 3] + "..." : str
    end

    # Track display state for a research round
    private class RoundDisplay
      property round : Int32
      property topic : String
      property worker_count : Int32
      property? completed : Bool

      def initialize(@round, @topic, @worker_count, @completed = false)
      end
    end
  end
end
