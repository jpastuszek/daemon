class Daemon
	def self.daemonize(pid_file, log_file = nil)
		exit if fork
		Process.setsid # become session leader
		exit if fork # and exits
		# now in child

		# try to lock before we kill stdin/out
		lock(pid_file)

		if log_file
			log = File.open(log_file, 'a')
		else
			log = '/dev/null'
		end

		# disconnect
		STDIN.reopen '/dev/null'
		STDOUT.reopen log
		STDERR.reopen log
	end

	def self.lock(pid_file)
		@pf = File.open(pid_file, File::RDWR | File::CREAT)
		fail "already running with pid: #{@pf.read.strip}" unless @pf.flock(File::LOCK_EX|File::LOCK_NB)
		@pf.truncate(0)
		@pf.write(Process.pid.to_s + "\n")
		@pf.flush
		# keep it open and locked
	end
end

