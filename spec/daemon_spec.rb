require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'daemon'

$pf = 'test.pid'

describe Daemon do
	it '#lock should create a pid file with current process pid' do
		Daemon.lock($pf)
		File.open($pf).read.should == "#{Process.pid}\n"
	end

	it '#lock should raise error if called twice on same pid file' do
		Daemon.lock($pf)
		lambda {
			Daemon.lock($pf)
		}.should raise_error Daemon::LockError
	end

	it 'should not call at_exit handler during deamonization' do
		pid = Process.pid
		at_exit do
			fail 'at_exit called' if pid != Process.pid
		end

		fork do
			Daemon.daemonize($pf, '/dev/stdout')
			exit! # dont call at_exit
		end
		Process.wait
	end

	after :each do
		File.unlink($pf) if File.exist?($pf)
	end
end

