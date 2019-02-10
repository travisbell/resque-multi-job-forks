require File.join(File.expand_path(File.dirname(__FILE__)), '/helper')

class TestRssReader < Test::Unit::TestCase

  def setup
    @object = Object.new
    @object.extend Resque::Plugins::MultiJobForks::RssReader
  end

  # support before/after ruby 2.4 without deprecation notice
  IntegerClass = 1.class

  def test_current_process_rss
    rss = @object.rss
    # not a very strict test, but have you ever seen a ruby process < 1Mb?
    # the "real" test is manual verification via top/ps/htop
    assert_equal IntegerClass, rss.class
    assert @object.rss > 1000
  end

  def test_rss_other_processes
    rss = @object.rss(1) # init is guaranteed to exist
    assert_equal IntegerClass, rss.class
    assert @object.rss > 1000
  end

  def test_rss_posix
    assert @object.rss_posix > 1000
  end

  if Resque::Plugins::MultiJobForks::RssReader::LINUX
    def test_rss_linux
      assert @object.rss_linux > 1000
    end
  end

end
