"use strict";

(function(global) {
	const __pika_rt_stdin_text = "__PIKA_STDIN__";
	const __pika_rt_encoder = typeof TextEncoder !== "undefined" ? new TextEncoder() : null;
	const __pika_rt_decoder = typeof TextDecoder !== "undefined" ? new TextDecoder("utf-8") : null;
	const __pika_rt_has_buffer = typeof Buffer !== "undefined";
	const __pika_rt_has_process = typeof process !== "undefined" && process.stdout && process.stderr;
	let __pika_rt_fs = null;
	if (__pika_rt_has_process && typeof require === "function") {
		try {
			__pika_rt_fs = require("fs");
		} catch (_) {
			__pika_rt_fs = null;
		}
	}
	const __pika_rt_stdin_bytes = __pika_rt_encoder ? __pika_rt_encoder.encode(__pika_rt_stdin_text) : new Uint8Array(0);
	let __pika_rt_stdin_buf = null;
	let __pika_rt_stdin_pos = 0;

	function __pika_rt_slice_info(val) {
		if (!val || typeof val !== "object") return null;
		if (typeof val.len !== "number" || val.data === undefined) return null;
		const off = val.off || 0;
		return { data: val.data, off, len: val.len };
	}

	function __pika_rt_utf8_bytes(s) {
		if (s === null || s === undefined) return new Uint8Array(0);
		if (__pika_rt_has_buffer) return Buffer.from(String(s), "utf8");
		if (__pika_rt_encoder) return __pika_rt_encoder.encode(String(s));
		const str = String(s);
		const out = new Uint8Array(str.length);
		for (let i = 0; i < str.length; i += 1) out[i] = str.charCodeAt(i) & 0xff;
		return out;
	}

	function __pika_rt_utf8_len(s) {
		return __pika_rt_utf8_bytes(s).length;
	}

	function __pika_rt_to_bytes(val, maxLen) {
		if (val === null || val === undefined) return new Uint8Array(0);
		if (val && val.__pika_ptr) {
			if (val.base !== undefined) {
				const off = val.offset || 0;
				const end = maxLen === undefined ? undefined : off + Math.max(0, maxLen | 0);
				if (val.base instanceof Uint8Array) return val.base.subarray(off, end);
				if (Array.isArray(val.base)) return Uint8Array.from(val.base.slice(off, end));
				if (__pika_rt_has_buffer && Buffer.isBuffer(val.base)) return val.base.subarray(off, end);
			}
			try {
				return __pika_rt_to_bytes(val.get(), maxLen);
			} catch (_) {
				return new Uint8Array(0);
			}
		}
		const slice = __pika_rt_slice_info(val);
		if (slice) {
			const bytes = __pika_rt_to_bytes(slice.data, slice.len);
			return bytes.subarray(slice.off, slice.off + slice.len);
		}
		if (val instanceof Uint8Array) return val;
		if (__pika_rt_has_buffer && Buffer.isBuffer(val)) return val;
		if (Array.isArray(val)) return Uint8Array.from(val);
		if (typeof val === "string") return __pika_rt_utf8_bytes(val);
		return __pika_rt_utf8_bytes(String(val));
	}

	function __pika_rt_copy_bytes(dst, src, count) {
		const n = Math.max(0, count | 0);
		const srcBytes = __pika_rt_to_bytes(src);
		let base = dst;
		let off = 0;
		let len = 0;
		const slice = __pika_rt_slice_info(dst);
		if (slice) {
			base = slice.data;
			off = slice.off;
			len = slice.len;
		} else if (dst && dst.__pika_ptr && dst.base !== undefined) {
			base = dst.base;
			off = dst.offset || 0;
			len = base.length;
		} else if (base instanceof Uint8Array || Array.isArray(base)) {
			len = base.length;
		} else if (__pika_rt_has_buffer && Buffer.isBuffer(base)) {
			len = base.length;
		} else {
			return;
		}
		const max = Math.min(n, len, srcBytes.length);
		for (let i = 0; i < max; i += 1) {
			base[off + i] = srcBytes[i];
		}
	}

	function __pika_rt_read_stdin() {
		if (__pika_rt_stdin_buf !== null) return;
		if (__pika_rt_fs) {
			try {
				__pika_rt_stdin_buf = __pika_rt_fs.readFileSync(0);
			} catch (_) {
				__pika_rt_stdin_buf = new Uint8Array(0);
			}
		} else {
			__pika_rt_stdin_buf = __pika_rt_stdin_bytes;
		}
		__pika_rt_stdin_pos = 0;
	}

	function __pika_rt_post(type, text) {
		if (typeof postMessage === "function") {
			postMessage({ type, text });
			return;
		}
		if (__pika_rt_has_process) {
			if (type === "stderr") process.stderr.write(text);
			else process.stdout.write(text);
			return;
		}
		if (type === "stderr" && console && console.error) {
			console.error(text);
		} else if (console && console.log) {
			console.log(text);
		}
	}

	function __pika_rt_strcmp(a, b) {
		const ba = __pika_rt_to_bytes(a);
		const bb = __pika_rt_to_bytes(b);
		if (ba.length !== bb.length) return 0;
		for (let i = 0; i < ba.length; i += 1) {
			if (ba[i] !== bb[i]) return 0;
		}
		return 1;
	}

	global.rt = {
		print(...args) {
			__pika_rt_post("stdout", args.join(" ") + "\n");
		},
		write(fd, buf, len) {
			const maxLen = len === undefined ? undefined : Math.max(0, len | 0);
			const bytes = __pika_rt_to_bytes(buf, maxLen);
			const max = bytes.length;
			const n = maxLen === undefined ? max : Math.min(max, maxLen);
			const out = bytes.subarray(0, n);
			let text = "";
			if (__pika_rt_decoder) {
				text = __pika_rt_decoder.decode(out);
			} else if (__pika_rt_has_buffer) {
				text = Buffer.from(out).toString("utf8");
			} else {
				for (let i = 0; i < out.length; i += 1) {
					text += String.fromCharCode(out[i]);
				}
			}
			__pika_rt_post(fd === 2 ? "stderr" : "stdout", text);
			return n;
		},
		read(fd, buf, count) {
			if (fd !== 0) return -1;
			__pika_rt_read_stdin();
			const bytes = __pika_rt_stdin_buf || __pika_rt_stdin_bytes;
			const available = bytes.length - __pika_rt_stdin_pos;
			if (available <= 0) return 0;
			const n = Math.min(available, count | 0);
			const chunk = bytes.subarray(__pika_rt_stdin_pos, __pika_rt_stdin_pos + n);
			__pika_rt_stdin_pos += n;
			__pika_rt_copy_bytes(buf, chunk, n);
			return n;
		},
		exit(status) {
			throw new Error("exit " + (status | 0));
		},
		abort(msg) {
			throw new Error(String(msg || "abort"));
		},
		abort_fixed(_file, line, col, code) {
			throw new Error("abort_fixed(" + code + ") at " + line + ":" + col);
		},
		memcpy(dst, src, n) {
			__pika_rt_copy_bytes(dst, src, n);
			return dst;
		},
		memmove(dst, src, n) {
			const temp = __pika_rt_to_bytes(src, Math.max(0, n | 0));
			__pika_rt_copy_bytes(dst, temp, temp.length);
			return dst;
		},
		memset(dst, val, n) {
			const value = val & 0xff;
			let base = dst;
			let off = 0;
			let len = 0;
			const slice = __pika_rt_slice_info(dst);
			if (slice) {
				base = slice.data;
				off = slice.off;
				len = slice.len;
			} else if (dst && dst.__pika_ptr && dst.base !== undefined) {
				base = dst.base;
				off = dst.offset || 0;
				len = base.length;
			} else if (base instanceof Uint8Array || Array.isArray(base)) {
				len = base.length;
			} else if (__pika_rt_has_buffer && Buffer.isBuffer(base)) {
				len = base.length;
			} else {
				return dst;
			}
			const max = Math.min(len, Math.max(0, n | 0));
			for (let i = 0; i < max; i += 1) {
				base[off + i] = value;
			}
			return dst;
		},
		strcmp(a, b) {
			return __pika_rt_strcmp(a, b);
		},
	};

	global.strings = {
		toutf8(s) {
			const bytes = __pika_rt_utf8_bytes(String(s));
			return { __pika_slice: true, data: bytes, off: 0, len: bytes.length, cap: bytes.length };
		},
		fromutf8_unsafe(bytes) {
			const out = __pika_rt_to_bytes(bytes);
			if (__pika_rt_decoder) return __pika_rt_decoder.decode(out);
			if (__pika_rt_has_buffer) return Buffer.from(out).toString("utf8");
			let text = "";
			for (let i = 0; i < out.length; i += 1) {
				text += String.fromCharCode(out[i]);
			}
			return text;
		},
	};
})(typeof globalThis !== "undefined" ? globalThis : (typeof window !== "undefined" ? window : this));
