require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'
#require "./validate-owl.rb"

TASK_SERVICE_URI = "http://ot-dev.in-silico.ch/task" 
#TASK_SERVICE_URI = "http://ot-test.in-silico.ch/task" 
#TASK_SERVICE_URI = "https://ambit.uni-plovdiv.bg:8443/ambit2/task" #not compatible

class TaskTest < Test::Unit::TestCase


=begin
=end
  def test_all
    all = OpenTox::Task.all(TASK_SERVICE_URI)
    assert_equal Array, all.class
    t = all.last
    assert_equal OpenTox::Task, t.class
    assert_equal RDF::OT1.Task, t[RDF.type]
  end

  def test_create_and_complete
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test" do
      sleep 1
      TASK_SERVICE_URI
    end
    assert task.running?
    assert_equal "Running", task.hasStatus
    task.wait
    assert task.completed?
    assert_equal "Completed", task.hasStatus
    assert_equal TASK_SERVICE_URI, task.resultURI
  end


  def test_create_and_cancel
    task = OpenTox::Task.create TASK_SERVICE_URI do
      sleep 2
      TASK_SERVICE_URI
    end
    assert task.running?
    task.cancel
    assert task.cancelled?
  end

  def test_create_and_fail
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test failure", :creator => "http://test.org/fake_creator" do
      sleep 1
      raise "A runtime error occured"
    end
    assert task.running?
    assert_equal "Running", task.hasStatus
    task.wait
    assert task.error?
    assert_equal "Error", task.hasStatus
  end

  def test_create_and_fail_with_opentox_error
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test failure", :creator => "http://test.org/fake_creator" do
      sleep 1
      raise OpenTox::Error.new 500, "An OpenTox::Error occured"
    end
    assert task.running?
    assert_equal "Running", task.hasStatus
    task.wait
    assert task.error?
    assert_equal "Error", task.hasStatus
  end

  def test_wrong_result_uri
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test wrong result uri", :creator => "http://test.org/fake_creator" do
      sleep 1
      "Asasadasd"
    end
    assert task.running?
    assert_equal "Running", task.hasStatus
    task.wait
    assert task.error?
    assert_equal "Error", task.hasStatus
  end
=begin
=end

end
