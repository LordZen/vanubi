/*
 *  Copyright © 2013 Luca Bruno
 *  Copyright © 2013 Rocco Folino
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
	public abstract class Comment {
		protected Buffer buf;
		protected int common_offset;

		protected abstract bool is_line_commented (int line);
		protected abstract void comment_line (int line);
		protected abstract void decomment_line (int line);

		public Comment (Buffer buf) {
			this.buf = buf;
			this.common_offset = int.MAX;
		}

		private void find_common_offset (int start_line, int end_line) {
			for (var i=start_line; i<=end_line; i++) {
				if (buf.empty_line (i)) {
					continue;
				}

				var iter = buf.line_start (i);
				iter.forward_spaces ();
				if (iter.line_offset < common_offset) {
					common_offset = iter.line_offset;
				}
			}
		}

		private int count_commented_lines (int start_line, int end_line) {
			var count = 0;
			for (var i=start_line; i<=end_line; i++) {
				if (is_line_commented (i) || buf.empty_line (i)) {
					count++;
				}
			}
			return count;
		}

		public virtual void toggle_comment (BufferIter start_iter, BufferIter end_iter) {
			var start_line = start_iter.line;
			var end_line = end_iter.line;
			var tot_lines = (end_line - start_line) + 1;

			debug ("start-line=%d end-line=%d tot-line=%d",
			       start_line, end_line, tot_lines);

			if (tot_lines == 0) {
				return;
			}

			if (tot_lines < 0) {
				/* Invalid region */
				warning ("Invalid comment region [tot-lines=%d]", tot_lines);
				return;
			}

			if (tot_lines == 1) { /* Processing single line */
				find_common_offset (start_line, start_line);
				if (is_line_commented (start_line)) {
					decomment_line (start_line);
				} else {
					comment_line (start_line);
				}
			} else { /* Processing region */
				var commented_lines = count_commented_lines (start_line, end_line);
				debug ("commented lines: %d", commented_lines);
				if (commented_lines == tot_lines) {
					/* Decomment all */
					for (var i=start_line; i<=end_line; i++) {
						decomment_line (i);
						debug ("decommenting line %d", i);
					}
				} else { /* Comment all and escape already commented lines */
					find_common_offset (start_line, end_line);
					for (var i=start_line; i<=end_line; i++) {
						comment_line (i);
						debug ("commenting line %d common-offset=%d", i, common_offset);
					}
				}
			}
		}
	}

	public class Comment_Default : Comment {
		public Comment_Default (Buffer buf) {
			base (buf);
		}

		protected override bool is_line_commented (int line) {
			return /\s*\/\*\s?.+\s?\*\//.match(buf.line_text (line));
		}

		protected void escape_line (int line) {
			var iter = buf.line_start (line);

			/* Escape forward */

			iter.forward_spaces ();

			while (!iter.eol) {
				if (iter.char == '/') {
					iter.forward_char ();

					if (!iter.eol && iter.char == '*') {
						buf.insert (iter, "\\");
						break;
					}
				} else {
					iter.forward_char ();
				}
			}

			iter = buf.line_end (line);

			/* Escape backward */

			iter.backward_spaces ();

			while (!iter.sol) {
				if (!iter.sol && iter.char == '/') {
					iter.backward_char ();

					if (!iter.sol && iter.char == '*') {
						iter.forward_char ();
						buf.insert (iter, "\\");
						break;
					}
				} else {
					iter.backward_char ();
				}
			}
		}

		protected void unescape_line (int line) {
			var iter = buf.line_start (line);

			/* Unescape forward */

			iter.forward_spaces ();

			while (!iter.eol) {
				if (iter.char == '/') {
					iter.forward_char ();

					if (!iter.eol && iter.char == '\\') {
						iter.forward_char ();

						if (!iter.eol && iter.char == '*') {
							/* End iter point to '*' */
							var end_iter = iter.copy ();
							iter.backward_char (); /* Got to '\' */
							buf.delete (iter, end_iter);
							break;
						}
					}
				} else {
					iter.forward_char ();
				}
			}

			iter = buf.line_end(line);

			/* Unescape backward */

			iter.backward_spaces ();

			while (!iter.sol) {
				if (iter.char == '/') {
					iter.backward_char ();

					if (!iter.sol && iter.char == '\\') {
						iter.backward_char ();

						if (!iter.sol && iter.char == '*') {
							iter.forward_char (); /* Got to '\' */
							var start_iter = iter.copy ();
							iter.forward_char (); /* Got to '/' */
							buf.delete (start_iter, iter);
							break;
						}
					}
				} else {
					iter.backward_char ();
				}
			}
		}

		protected override void comment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}

			if (is_line_commented (line)) {
				escape_line (line);
			}

			var start_iter = buf.line_at_char (line, common_offset);
			buf.insert (start_iter, "/* ");
			var end_iter = buf.line_end (start_iter.line);
			buf.insert (end_iter, " */");
		}

		protected override void decomment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			if (is_line_commented (line)) {
				var iter = buf.line_start (line);
				iter.forward_spaces ();
				var del_iter = iter.copy ();
				iter.forward_char (); /* Skip '/' */
				iter.forward_char (); /* Skip '*' */
				if (iter.char == ' ')
					iter.forward_char (); /* Skip ' ' */
				buf.delete (del_iter, iter);
				iter = buf.line_end (line);
				iter.backward_spaces ();
				iter.forward_char(); /* Must point after '/' */
				del_iter = iter.copy ();
				iter.backward_char (); /* Skip '/' */
				iter.backward_char (); /* Skip '*' */
				iter.backward_char (); /* Skip ' ' */
				if (iter.char != ' ')
					iter.forward_char();
				buf.delete (iter, del_iter);
				unescape_line (line);
			}
		}
	}

	public class Comment_Hash : Comment {
		public Comment_Hash (Buffer buf) {
			base (buf);
		}

		protected override bool is_line_commented (int line) {
			return /\s*#\s?.*/.match(buf.line_text (line));
		}

		protected override void comment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			var iter = buf.line_at_char (line, common_offset);
			buf.insert (iter, "# ");
		}

		protected override void decomment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			if (is_line_commented (line)) {
				var iter = buf.line_start (line);
				iter.forward_spaces ();
				var del_iter = iter.copy ();
				iter.forward_char (); /* Skip '#' */
				if (iter.char == ' ')
					iter.forward_char (); /* Skip ' ' */
				buf.delete (del_iter, iter);
			}
		}
	}

	public class Comment_Asm : Comment {
		public Comment_Asm (Buffer buf) {
			base (buf);
		}

		protected override bool is_line_commented (int line) {
			return /\s*;\s?.*/.match(buf.line_text (line));
		}

		protected override void comment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			var iter = buf.line_at_char (line, common_offset);
			buf.insert (iter, "; ");
		}

		protected override void decomment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			if (is_line_commented (line)) {
				var iter = buf.line_start (line);
				iter.forward_spaces ();
				var del_iter = iter.copy ();
				iter.forward_char (); /* Skip ';' */
				if (iter.char == ' ')
					iter.forward_char (); /* Skip ' ' */
				buf.delete (del_iter, iter);
			}
		}
	}

	public class Comment_Lua : Comment {
		public Comment_Lua (Buffer buf) {
			base (buf);
		}

		protected override bool is_line_commented (int line) {
			/* XXX: evaluate support "---" commenting */
			return /\s*--\s?.*/.match(buf.line_text (line));
		}

		protected override void comment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			var iter = buf.line_at_char (line, common_offset);
			buf.insert (iter, "-- ");
		}

		protected override void decomment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			if (is_line_commented (line)) {
				var iter = buf.line_start (line);
				iter.forward_spaces ();
				var del_iter = iter.copy ();
				iter.forward_char (); /* Skip '-' */
				iter.forward_char (); /* Skip '-' */
				if (iter.char == ' ')
					iter.forward_char (); /* Skip ' ' */
				buf.delete (del_iter, iter);
			}
		}
	}

	public class Comment_Markup : Comment {
		public Comment_Markup (Buffer buf) {
			base (buf);
		}

		protected override bool is_line_commented (int line) {
			return /^<!--.*-->$/.match (buf.line_text (line).strip ());
		}

		protected void escape_line (int line) {
			// no escape for now
		}

		protected void unescape_line (int line) {
			// no unescape for now
		}

		protected override void comment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}

			if (is_line_commented (line)) {
				escape_line (line);
			}

			var start_iter = buf.line_at_char (line, common_offset);
			buf.insert (start_iter, "<!-- ");
			var end_iter = buf.line_end (start_iter.line);
			buf.insert (end_iter, " -->");
		}

		protected override void decomment_line (int line) {
			if (buf.empty_line (line)) {
				return;
			}
			if (is_line_commented (line)) {
				var iter = buf.line_start (line);
				iter.forward_spaces ();
				var del_iter = iter.forward_string ("<!-- ");
				buf.delete (iter, del_iter);

				iter = buf.line_end (line);
				iter.backward_spaces ();
				iter.forward_char(); /* Must point after '>' */
				del_iter = iter.backward_string (" -->");
				buf.delete (del_iter, iter);
				unescape_line (line);
			}
		}
	}

}
