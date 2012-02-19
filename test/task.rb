require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'
#require "./validate-owl.rb"

#TASK_SERVICE_URI = "http://ot-dev.in-silico.ch/task" 
TASK_SERVICE_URI = "http://ot-test.in-silico.ch/task" 
#TASK_SERVICE_URI = "https://ambit.uni-plovdiv.bg:8443/ambit2/task" #not compatible

class TaskTest < Test::Unit::TestCase


  def test_all
    t = OpenTox::Task.all(TASK_SERVICE_URI)
    assert_equal Array, t.class
    assert_equal RDF::OT1.Task, t.last.metadata[RDF.type]
  end

  def test_create_and_complete
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test" do
      sleep 1
      TASK_SERVICE_URI
    end
    assert_equal "Running", task.hasStatus
    task.wait_for_completion
    assert_equal "Completed", task.hasStatus
    assert_equal TASK_SERVICE_URI, task.resultURI
  end

  def test_rdf
    task = OpenTox::Task.all(TASK_SERVICE_URI).last
    assert_equal OpenTox::Task, task.class
    #validate_owl(task.uri)
  end

  def test_create_and_fail
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test failure", :creator => "http://test.org/fake_creator" do
      sleep 1
      raise "an error occured"
    end
    assert_equal "Running", task.hasStatus
    task.wait_for_completion
    assert_equal "Error", task.hasStatus
  end

  def test_wrong_result_uri
    task = OpenTox::Task.create TASK_SERVICE_URI, :description => "test wrong result uri", :creator => "http://test.org/fake_creator" do
      sleep 1
      "Asasadasd"
    end
    assert_equal "Running", task.hasStatus
    task.wait_for_completion
    assert_equal "Error", task.hasStatus
  end

end
