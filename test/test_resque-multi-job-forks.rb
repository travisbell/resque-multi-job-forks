require File.join(File.expand_path(File.dirname(__FILE__)), '/helper')

class TestResqueMultiJobForks < Test::Unit::TestCase
  def setup
    $SEQ_READER, $SEQ_WRITER = IO.pipe
    $redis.flushdb
    @worker = Resque::Worker.new(:jobs)
  end

  def test_timeout_limit_sequence_of_events
    @worker.log_with_severity :debug, "in test_timeout_limit_sequence_of_events"
    # only allow enough time for 3 jobs to process.
    @worker.seconds_per_fork = 3

    Resque.enqueue(SequenceJob, 1)
    Resque.enqueue(SequenceJob, 2)
    Resque.enqueue(SequenceJob, 3)
    Resque.enqueue(SequenceJob, 4)

    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    # test the sequence is correct.
    assert_equal([:before_fork, :after_fork, :work_1, :work_2, :work_3,
                  :before_child_exit_3, :before_fork, :after_fork, :work_4,
                  :before_child_exit_1], sequence, 'correct sequence')
  end

  def test_graceful_shutdown_during_first_job
    @worker.log_with_severity :debug, "in test_graceful_shutdown_during_first_job"
    # enough time for all jobs to process.
    @worker.seconds_per_fork = 60

    Resque.enqueue(SequenceJob, 1)
    Resque.enqueue(SequenceJob, 2)
    t = Thread.new do
      sleep 1 # before first job can complete
      @worker.shutdown
    end
    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    # test the sequence is correct.
    assert_equal([:before_fork, :after_fork, :work_1,
                  :before_child_exit_1], sequence, 'correct sequence')
    t.join
  end

  def test_immediate_shutdown_during_first_job
    @worker.log_with_severity :debug, "in test_immediate_shutdown_during_first_job"
    # enough time for all jobs to process.
    @worker.seconds_per_fork = 60
    @worker.term_child = false

    Resque.enqueue(SequenceJob, 1)
    Resque.enqueue(SequenceJob, 2)
    t = Thread.new do
      sleep 0.5 # before first job can complete
      Process.kill("INT", @worker.pid) # triggers shutdown! in main thread
    end
    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    # test the sequence is correct.
    assert_equal([:before_fork, :after_fork], sequence, 'correct sequence')
    t.join
  end

  def test_sigterm_shutdown_during_first_job
    @worker.log_with_severity :debug, "in test_sigterm_shutdown_during_first_job"
    # enough time for all jobs to process.
    @worker.seconds_per_fork = 60
    @worker.term_child = true
    @worker.term_timeout = 0.5

    Resque.enqueue(SequenceJob, 1)
    Resque.enqueue(SequenceJob, 2)
    t = Thread.new do
      sleep 1.0 # before first job can complete
      Process.kill("INT", @worker.pid) # triggers shutdown! in main thread
    end
    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    # test the sequence is correct.
    assert_equal([:before_fork, :after_fork, :failed_job_resque_termexception,
                  :before_child_exit_1], sequence, 'correct sequence')
    t.join
  end

  def test_shutdown_between_jobs
    @worker.log_with_severity :debug, "in test_sigterm_shutdown_during_first_job"
    # enough time for all jobs to process.
    @worker.seconds_per_fork = 60
    @worker.term_child = true
    @worker.graceful_term = true
    @worker.term_timeout = 0.5
    @worker.start_lag = 1

    Resque.enqueue(QuickSequenceJob, 1)
    Resque.enqueue(SequenceJob, 2)
    t = Thread.new do
      sleep 2
      Process.kill("TERM", @worker.pid)
    end
    @worker.work(0)
    $SEQ_WRITER.close

    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }
    assert_equal([:before_fork, :after_fork, :work_1, :before_child_exit_1, :failed_job_resque_worker_workerterminated], sequence, 'correct sequence')

    t.join
  end

  # test we can also limit fork job process by a job limit.
  def test_job_limit_sequence_of_events
    @worker.log_with_severity :debug, "in test_job_limit_sequence_of_events"
    # only allow 20 jobs per fork
    ENV['JOBS_PER_FORK'] = '20'

    # queue 40 jobs.
    (1..40).each { |i| Resque.enqueue(QuickSequenceJob, i) }

    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    assert_equal(%i[
      before_fork after_fork
      work_1 work_2 work_3 work_4 work_5
      work_6 work_7 work_8 work_9 work_10
      work_11 work_12 work_13 work_14 work_15
      work_16 work_17 work_18 work_19 work_20
      before_child_exit_20
      before_fork after_fork
      work_21 work_22 work_23 work_24 work_25
      work_26 work_27 work_28 work_29 work_30
      work_31 work_32 work_33 work_34 work_35
      work_36 work_37 work_38 work_39 work_40
      before_child_exit_20
    ], sequence, 'correct sequence')
  end

  def teardown
    # make sure we don't clobber any other tests.
    ENV['JOBS_PER_FORK'] = nil
    Resque::Worker.kill_all_heartbeat_threads
  end

end
