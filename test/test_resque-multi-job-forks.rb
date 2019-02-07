require File.join(File.expand_path(File.dirname(__FILE__)), '/helper')

class TestResqueMultiJobForks < Test::Unit::TestCase
  def setup
    $SEQ_READER, $SEQ_WRITER = IO.pipe
    $redis.flushdb
    @worker = Resque::Worker.new(:jobs)
  end

  def test_timeout_limit_sequence_of_events
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
    assert_equal([:before_fork, :after_fork,
                  :before_child_exit_1], sequence, 'correct sequence')
    t.join
  end

  # test we can also limit fork job process by a job limit.
  def test_job_limit_sequence_of_events
    # only allow 20 jobs per fork
    ENV['JOBS_PER_FORK'] = '20'

    # queue 40 jobs.
    (1..40).each { |i| Resque.enqueue(QuickSequenceJob, i) }

    # INTERVAL=0 will exit when no more jobs left
    @worker.work(0)
    $SEQ_WRITER.close
    sequence = $SEQ_READER.each_line.map {|l| l.strip.to_sym }

    assert_equal :before_fork,          sequence[0],  'first before_fork call.'
    assert_equal :after_fork,           sequence[1],  'first after_fork call.'
    assert_equal :work_20,              sequence[21], '20th chunk of work.'
    assert_equal :before_child_exit_20, sequence[22], 'first before_child_exit call.'
    assert_equal :before_fork,          sequence[23], 'final before_fork call.'
    assert_equal :after_fork,           sequence[24], 'final after_fork call.'
    assert_equal :work_40,              sequence[44], '40th chunk of work.'
    assert_equal :before_child_exit_20, sequence[45], 'final before_child_exit call.'
  end

  def teardown
    # make sure we don't clobber any other tests.
    ENV['JOBS_PER_FORK'] = nil
  end
end
