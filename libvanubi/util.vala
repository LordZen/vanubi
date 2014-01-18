/*
 *  Copyright © 2011-2014 Luca Bruno
 *
 *  This file is part of Vanubi.
 *
 *  Vanubi is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Vanubi is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Vanubi.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Vanubi {
	/* Useful for functional combinators.
	   Return false to quit the loop. */
	public delegate bool Operation<G> (G object);

	public delegate G TaskFunc<G> () throws Error;

	public class Location : Object {
		public DataSource? source;
		public int start_line;
		public int start_column;
		public int end_line;
		public int end_column;
		
		public Location (owned DataSource? source, int start_line = -1, int start_column = -1, int end_line = -1, int end_column = -1) {
			this.source = (owned) source;
			this.start_line = start_line;
			this.start_column = start_column;
			this.end_line = end_line;
			this.end_column = end_column;
		}
		
		public string to_string () {
			var s = "";
			if (source != null) {
				s += source.to_string ();
			}
			if (start_line >= 0) {
				s += ":"+start_line.to_string ();
				if (start_column >= 0) {
					s += "."+start_column.to_string();
				}
			}
			if (end_line >= 0) {
				s += "-"+end_line.to_string ();
				if (end_column >= 0) {
					s += "."+end_column.to_string();
				}
			}
			return s;
		}
	}
	
	ThreadPool<ThreadWorker> thread_pool = null;
	
	class ThreadWorker {
		public ThreadFunc task_func;
		
		public ThreadWorker (owned ThreadFunc task_func) {
			this.task_func = (owned) task_func;
		}
	}
	
	void initialize_thread_pool () {
		if (thread_pool != null) {
			return;
		}
		try {
			thread_pool = new ThreadPool<ThreadWorker>.with_owned_data ((worker) => {
					// Call worker.run () on thread-start
					worker.task_func ();
			}, 20, false);
		} catch (Error e) {
			error ("Could not initialize thread pool: %s".printf (e.message));
		}
		ThreadPool.set_max_unused_threads (2);
	}

	public async G run_in_thread<G> (owned TaskFunc<G> func, int io_priority = GLib.Priority.DEFAULT) throws Error {
		initialize_thread_pool ();
		SourceFunc resume = run_in_thread.callback;
		Error err = null;
		G result = null;

		thread_pool.add (new ThreadWorker (() => {
				try {
					result = func ();
				} catch (Error e) {
					err = e;
				}
				Idle.add_full (io_priority, (owned) resume);
				return null;
		}));
		yield;
		if (err != null) {
			throw err;
		}
		return result;
	}

	public async uint8[] read_all_async (InputStream is, Cancellable? cancellable = null) throws Error {
		uint8[] res = new uint8[1024];
		ssize_t offset = 0;
		ssize_t read = 0;
		while (true) {
			if (read > 512) {
				res.resize (res.length+1024);
			}
			unowned uint8[] buffer = (uint8[])(((uint8*)res)+offset);
			buffer.length = (int)(res.length-offset);
			read = yield is.read_async (buffer, Priority.DEFAULT, cancellable);
			if (read == 0) {
				return res;
			}
			offset += read;
		}
	}
	
	public async extern void spawn_async_with_pipes (string? working_directory, [CCode (array_length = false, array_null_terminated = true)] string[] argv, [CCode (array_length = false, array_null_terminated = true)] string[]? envp, SpawnFlags _flags, SpawnChildSetupFunc? child_setup, int io_priority, Cancellable? cancellable, out Pid child_pid, out int standard_input = null, out int standard_output = null, out int standard_error = null) throws SpawnError;
	
	public async uint8[] execute_shell_async (File? working_dir, string command_line, uint8[]? input = null, out uint8[] errors = null, out int status = null, Cancellable? cancellable = null) throws Error {
		string[] argv = {"bash", "-c", command_line};
		int stdin, stdout, stderr;
		Pid child_pid;
		yield spawn_async_with_pipes (working_dir.get_path (), argv, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null, Priority.DEFAULT, cancellable, out child_pid, out stdin, out stdout, out stderr);
		
		int st = 0xdead;
		bool requires_resume = false;
		ChildWatch.add (child_pid, (pid, sta) => {
			// Triggered when the child indicated by child_pid exits
			Process.close_pid (pid);
			st = sta;
			if (requires_resume) {
				execute_shell_async.callback ();
			}
		});
		
		var os = new UnixOutputStream (stdin, true);
		if (input != null) {
			yield os.write_async (input, Priority.DEFAULT, cancellable);
		}
		os.close ();
		
		var is = new UnixInputStream (stdout, true);
		var res = yield read_all_async (is, cancellable);
		
		var eis = new UnixInputStream (stderr, true);
		errors = yield read_all_async (is, cancellable);
		
		is.close ();
		eis.close ();
		
		if (st == 0xdead) {
			requires_resume = true;
			// wait till child watch
			yield;
		}
		status = st;
		return res;
	}
	
	static Regex update_copyright_year_regex1 = null;
	static Regex update_copyright_year_regex2 = null;
	
	// Returns true if any copyright year has been replaced
	public bool update_copyright_year (Buffer buf) {
		if (update_copyright_year_regex1 == null || update_copyright_year_regex2 == null) {
			try {
				update_copyright_year_regex1 = new Regex ("Copyright.*\\d\\d\\d\\d-(\\d\\d\\d\\d)", RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS);
				update_copyright_year_regex2 = new Regex ("Copyright.*(\\d\\d\\d\\d)", RegexCompileFlags.OPTIMIZE | RegexCompileFlags.CASELESS);
			} catch (Error e) {
				warning (e.message);
				return false;
			}
		}
		var year = new DateTime.now_local ().get_year ();
		
		var iter = buf.line_start (0);
		// find the first comment in the first 10 lines of the file and replace the copyright year
		while (!iter.eof && iter.line < 10) {
			while (!iter.is_in_comment && !iter.eof && iter.line < 10) iter.forward_char ();
			if (iter.is_in_comment) {
				// found a line with a comment
				var text = buf.line_text (iter.line);
				
				MatchInfo info;
				if (update_copyright_year_regex1.match (text, 0, out info)) {
					var cur_year = info.fetch (1);
					if (cur_year == year.to_string ()) {
						// already up-to-date
						return false;
					}
					
					int pos;
					info.fetch_pos (1, out pos, null);
					iter = buf.line_at_byte (iter.line, pos);
					var end = buf.line_at_byte (iter.line, pos+4);
					buf.delete (iter, end);
					buf.insert (iter, year.to_string ());
					return true;
				} else if (update_copyright_year_regex2.match (text, 0, out info)) {
					var cur_year = info.fetch (1);
					if (cur_year == year.to_string ()) {
						// already up-to-date
						return false;
					}
					
					int pos;
					info.fetch_pos (1, out pos, null);
					iter = buf.line_at_byte (iter.line, pos);
					var end = buf.line_at_byte (iter.line, pos+4);
					buf.delete (iter, end);
					buf.insert (iter, @"$cur_year-$year");
					return true;
				}
				
				while (!iter.eol) iter.forward_char ();
				if (iter.eof) {
					break;
				}
				iter.forward_char ();
			}
		}
		
		return false;
	}
	
	public class AsyncDataInputStream : DataInputStream {
		public AsyncDataInputStream (InputStream base_stream) {
			Object (base_stream: base_stream);
		}
		
		public async void ensure_filled (ssize_t size, int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
			if (get_available () < size) {
				var res = yield fill_async (size, io_priority, cancellable);
				if (res <= 0) {
					throw new IOError.PARTIAL_INPUT ("Could not fill buffer for size: "+size.to_string ());
				}
			}
		}
		
		public async int32 read_int32_async (int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
			yield ensure_filled ((ssize_t) sizeof (int32));
			return read_int32 (cancellable);
		}
		
		public async int32 read_byte_async (int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
			yield ensure_filled ((ssize_t) sizeof (uint8));
			return read_byte (cancellable);
		}
		
		public async string read_zero_terminated_string (int io_priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
			return yield read_upto_async ("\0", 1, io_priority, cancellable, null);
		}
	}
}
