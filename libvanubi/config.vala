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
	public class Configuration {
		KeyFile backend;
		File file;
		Cancellable saving_cancellable;
		public FileCluster cluster;

		public Configuration () {
			cluster = new FileCluster (this);
			
			var home = Environment.get_home_dir ();
			var filename = Path.build_filename (home, ".vanubi");
			backend = new KeyFile ();
			file = File.new_for_path (filename);
			if (file.query_exists ()) {
				try {
					backend.load_from_file (filename, KeyFileFlags.NONE);
					check_config ();
				} catch (Error e) {
					warning ("Could not load vanubi configuration: %s", e.message);
				}
			}
		}

		public void check_config () {
			var version = get_global_int ("config_version", 0);
			migrate (version);
		}
		
		public void migrate (int from_version) {
		}
		
		public int get_group_int (string group, string key, int default) {
			try {
				if (backend.has_group (group) && backend.has_key (group, key)) {
					return backend.get_integer (group, key);
				}
				return default;
			} catch (Error e) {
				return default;
			}
		}

		public void set_group_int (string group, string key, int size) {
			backend.set_integer (group, key, size);
		}

		public string? get_group_string (string group, string key, string? default = null) {
			try {
				if (backend.has_group (group) && backend.has_key (group, key)) {
					return backend.get_string (group, key);
				}
				return default;
			} catch (Error e) {
				return default;
			}
		}
		
		public void remove_group_key (string group, string key) {
			try {
				backend.remove_key (group, key);
			} catch (Error e) {
			}
		}

		public void set_group_string (string group, string key, string value) {
			backend.set_string (group, key, value);
		}
		
		public bool has_group_key (string group, string key) {
			try {
				return backend.has_key (group, key);
			} catch (Error e) {
				return false;
			}
		}

		/* Global */
		public string get_global_string (string key, string? default = null) {
			return get_group_string ("Global", key, default);
		}
		
		public int get_global_int (string key, int default = 0) {
			return get_group_int ("Global", key, default);
		}
		
		public void set_global_int (string key, int value) {
			set_group_int ("Global", key, value);
		}

		/* Editor */
		public int get_editor_int (string key, int default = 0) {
			return get_group_int ("Editor", key, default);
		}
		
		public void set_editor_int (string key, int value) {
			set_group_int ("Editor", key, value);
		}

		public string? get_editor_string (string key, string? default = null) {
			return get_group_string ("Editor", key, default);
		}

		/* File */
		// get files except *scratch*
		public File[] get_files () {
			File[] res = null;
			var groups = backend.get_groups ();
			foreach (unowned string group in groups) {
				if (group.has_prefix ("file://")) {
					res += File.new_for_uri (group);
				}
			}
			return res;
		}
		
		public string? get_file_string (File? file, string key, string? default = null) {
			var group = file != null ? file.get_uri () : "*scratch*";
			if (file != null && !has_group_key (group, key)) {
				// look into a similar file
				group = cluster.get_similar_file(file, key, default != null).get_uri ();
			}
			return get_group_string (group, key, get_editor_string (key, default));
		}
		
		public void set_file_string (File? file, string key, string value) {
			var group = file != null ? file.get_uri () : "*scratch*";
			backend.set_string (group, key, value);
		}
		
		public void remove_file_key (File? file, string key) {
			var group = file != null ? file.get_uri () : "*scratch*";
			remove_group_key (group, key);
		}
		
		public async void save () {
			/* We save the file asynchronously (including the backup),
			   so that the user does not experience any UI lag. */
			var saving_data = backend.to_data ();
			if (saving_cancellable != null && !saving_cancellable.is_cancelled ()) {
				// Cancel any previous save() operation 
				saving_cancellable.cancel ();
			}
			saving_cancellable = new Cancellable ();
			try {
				yield file.replace_contents_async (saving_data.data, null, true, FileCreateFlags.PRIVATE, saving_cancellable, null);
			} catch (IOError.CANCELLED e) {
			} catch (Error e) {
				// TODO: display error message
				warning ("Could not save file: %s", e.message);
			}
		}
	}
}
