/*
 *  Copyright © 2011-2013 Luca Bruno
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
	public delegate G TaskFunc<G> () throws Error;

	public class Location {
		public File? file;
		public int start_line;
		public int start_column;
		public int end_line;
		public int end_column;
		
		public Location (File? file, int start_line = -1, int start_column = -1, int end_line = -1, int end_column = -1) {
			this.file = file;
			this.start_line = start_line;
			this.start_column = start_column;
			this.end_line = end_line;
			this.end_column = end_column;
		}
		
		public string to_string () {
			var s = "";
			if (file != null) {
				s += file.get_path ();
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

	public async G run_in_thread<G> (owned TaskFunc<G> func) throws Error {
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
				Idle.add ((owned) resume);
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
	
	public async uint8[] execute_shell_async (File? base_file, string command_line, uint8[]? input = null, Cancellable? cancellable = null) throws Error {
		/*string[] cmd_argv;
		Shell.parse_argv (command_line, out argv);*/
		string[] argv = {"sh", "-c", command_line};
		int stdin, stdout;
		Process.spawn_async_with_pipes (get_base_directory (base_file), argv, null, SpawnFlags.SEARCH_PATH, null, null, out stdin, out stdout, null);
		
		var os = new UnixOutputStream (stdin, true);
		yield os.write_async (input, Priority.DEFAULT, cancellable);
		os.close ();
		
		var is = new UnixInputStream (stdout, true);
		var res = yield read_all_async (is, cancellable);
		is.close ();
		return res;
	}
}
