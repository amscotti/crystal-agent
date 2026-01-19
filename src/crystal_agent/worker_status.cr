module CrystalAgent
  # Status update from a worker
  enum WorkerAction
    Starting
    Searching
    Fetching
    Thinking
    Completed
    Failed
  end

  struct WorkerStatus
    getter worker_id : Int32
    getter action : WorkerAction
    getter details : String
    getter task : String
    getter round : Int32

    def initialize(@worker_id, @task, @action, @details = "", @round = 1)
    end
  end

  # Research round tracking
  struct ResearchRound
    getter round_number : Int32
    getter topic : String
    getter worker_count : Int32
    getter? completed : Bool

    def initialize(@round_number, @topic, @worker_count = 0, @completed = false)
    end
  end
end
