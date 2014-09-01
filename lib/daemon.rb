class Daemon
	class LockError < RuntimeError
		def initialize(pid_file)
			super("cannot lock pid file '#{pid_file.path}', process already running with pid: #{pid_file.read.strip}")
		end
	end

	def self.daemonize(pid_file, log_file = nil, sync = true)
		# become new process group leader
		fence

		# try to lock before we kill stdin/out
		lock(pid_file)

		# close I/O
		disconnect(log_file, sync)
	end

	def self.fence
		exit! if fork
		Process.setsid # become new session leader
		# now in child
	end

	def self.lock(pid_file)
		pf = File.open(pid_file, File::RDWR | File::CREAT)
		raise LockError, pf unless pf.flock(File::LOCK_EX|File::LOCK_NB)
		pf.truncate(0)
		pf.write(Process.pid.to_s + "\n")
		pf.flush

		@pf = pf # keep it open and locked until process exits
	end

	def self.disconnect(log_file = nil, sync = true)
		if log_file
			log = File.open(log_file, 'ab')
			log.sync = sync
		else
			log = '/dev/null'
		end

		# disconnect
		STDIN.reopen '/dev/null'
		STDOUT.reopen log
		STDERR.reopen log
	end
end

