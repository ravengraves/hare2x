// strings module - str <-> []u8 conversions

export type maybestr = (str | !void);

@symbol("strings_toutf8") fn c_toutf8(s: str) []u8;
@symbol("strings_fromutf8_unsafe") fn c_fromutf8_unsafe(s: []u8) str;
@symbol("strings_dup") fn c_dup(s: str) maybestr;

export fn toutf8(s: str) []u8 = c_toutf8(s);

export fn fromutf8_unsafe(s: []u8) str = c_fromutf8_unsafe(s);

export fn dup(s: str) maybestr = { return c_dup(s); };
