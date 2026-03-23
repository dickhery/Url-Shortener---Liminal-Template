import Array "mo:core/Array";
import Iter "mo:core/Iter";
import Char "mo:core/Char";
import Nat8 "mo:core/Nat8";
import Result "mo:core/Result";
import Text "mo:core/Text";
import { unreachable; trap } "mo:core/Runtime";
import Nat32 "mo:core/Nat32";

/// Function to convert between hex and byte arrays
module {

  type Iter<T> = Iter.Iter<T>;
  type Result<T> = Result.Result<T, Text>;

  /// Type for format options.
  public type Format = {
    pre : Text;
    post : Text;
    sep : Text;
    preItem : Text;
    empty : Text;
    upper : Bool;
  };

  /// Type for format options of two dimensional arrays of bytes.
  public type Format2D = {
    inner : Format;
    outer : Format;
  };

  /// A `Format` constant for compact hexadecimal representation (no prefixes, postfixes, or separators).
  public let COMPACT : Format = {
    pre = "";
    post = "";
    sep = "";
    preItem = "";
    empty = "";
    upper = false;
  };

  /// A `Format` constant for compact hexadecimal representation with upper case hex values.
  public let COMPACT_UPPER : Format = {
    pre = "";
    post = "";
    sep = "";
    preItem = "";
    empty = "";
    upper = true;
  };

  /// A `Format` constant for compact hexadecimal representation with a single "0x" prefix for the entire string.
  public let COMPACT_PREFIX : Format = {
    pre = "0x";
    post = "";
    sep = "";
    preItem = "";
    empty = "";
    upper = false;
  };

  /// A `Format` constant for verbose hexadecimal representation, including brackets, "0x" prefixes for items, and comma separators.
  public let VERBOSE : Format = {
    pre = "[ ";
    post = " ]";
    sep = ", ";
    preItem = "0x";
    empty = "[]";
    upper = false;
  };

  /// A `Format` constant for verbose hexadecimal representation with upper case hex values, including brackets, "0x" prefixes for items, and comma separators.
  public let VERBOSE_UPPER : Format = {
    pre = "[ ";
    post = " ]";
    sep = ", ";
    preItem = "0x";
    empty = "[]";
    upper = true;
  };

  /// A `Format2D` constant for compact two-dimensional hexadecimal representation.
  public let COMPACT_2D : Format2D = {
    inner = {
      pre = "";
      post = "";
      sep = "";
      preItem = "";
      empty = "0";
      upper = false;
    };
    outer = {
      pre = "[";
      post = "]";
      sep = ", ";
      preItem = "";
      empty = "[]";
      upper = false;
    };
  };

  /// A `Format2D` constant for verbose two-dimensional hexadecimal representation.
  public let VERBOSE_2D : Format2D = {
    inner = VERBOSE;
    outer : Format = {
      pre = "[ ";
      post = " ]";
      sep = ", ";
      preItem = "";
      empty = "[ ]";
      upper = false;
    };
  };

  /// A `Format2D` constant for a matrix-like representation of two-dimensional hexadecimal arrays.
  public let MATRIX_2D : Format2D = {
    inner = {
      pre = "[ ";
      post = " ]";
      sep = ", ";
      preItem = "0x";
      empty = "[ ]";
      upper = false;
    };
    outer : Format = {
      pre = "[ ";
      post = " ]";
      sep = ",\n  ";
      preItem = "";
      empty = "[ ]";
      upper = false;
    };
  };

  /// Access elements of an iterator two at a time.
  /// Traps if `iter` contains an odd number of elements.
  func pairs<T>(iter : Iter<T>) : Iter<(T, T)> {

    func next() : ?(T, T) {
      switch (iter.next(), iter.next()) {
        case (?a, ?b) { return ?(a, b) };
        case (?_, null) {
          trap("Warning: discard last (odd) element from iterator in pairs()");
          return null;
        };
        case (null, ?_) { unreachable() };
        case (null, null) return null;
      };
    };

    return { next };
  };

  /// Add a single element in front of an iterator.
  /// If you need to prepend more than one element, consider using `Iter.flatten` instead.
  func prepend<T>(element : T, iter : Iter<T>) : Iter<T> {
    var first = true;
    return {
      next = func() : ?T {
        if (first) {
          first := false;
          return ?element;
        } else {
          iter.next();
        };
      };
    };
  };

  /// Convert a byte array to hex Text.
  public func toText(bytes : [Nat8]) : Text {
    var out = "";
    for (byte in bytes.vals()) {
      // Text.join uses a similar loop with `#=` so performance should be same or better compared to Iter.map |> Text.join
      out #= encodeByte(byte);
    };
    return out;
  };

  /// Convert a byte array to hex Text with custom separator.
  /// ```motoko
  /// let options = { pre = "[ "; post = " ]"; sep = ", "; itemPre = "0x"; empty = "[]" };
  /// let hex = toTextFormat([1, 2], options)
  /// assert hex == "[ 0x01, 0x02 ]"
  /// ```
  public func toTextFormat(
    bytes : [Nat8],
    options : Format,
  ) : Text {
    if (bytes == []) return options.empty;
    let encoder = if (options.upper) encodeByteUpper else encodeByte;
    let texts = Array.map<Nat8, Text>(bytes, func(b) { return options.preItem # encoder(b) });
    return options.pre # Text.join(options.sep, texts.vals()) # options.post;
  };

  /// Convert an array of byte arrays to hex Text.
  public func toText2D(bytess : [[Nat8]]) : Text {
    let texts = Array.map<[Nat8], Text>(bytess, func(bs) { if (bs == []) "0" else toText(bs) });
    return "[" # Text.join(", ", texts.vals()) # "]";
  };

  /// Convert an array of byte arrays to hex Text with custom separator.
  /// ```motoko
  /// let options = { pre = "< "; post = " >"; sep = " ; "; empty = "?" };
  /// let hex = toText2DFormat([[1, 2], []], options)
  /// assert hex == "< 0102 ; ? >"
  /// ```
  public func toText2DFormat(
    bytess : [[Nat8]],
    options : Format2D,
  ) : Text {
    if (bytess == []) return options.outer.empty;
    let texts = Array.map<[Nat8], Text>(bytess, func(bs) = toTextFormat(bs, options.inner));
    return options.outer.pre # Text.join(options.outer.sep, texts.vals()) # options.outer.post;
  };

  /// Convert hex Text into a byte array.
  /// The input must only contain hexadecimal chars (upper or lower case)
  /// It the hex text is of odd length, it will assume a leading 0.
  public func toArray(hex : Text) : Result<[Nat8]> {
    let chars = hex.size();
    let charsEven = chars % 2 == 0;
    let size = if charsEven { chars / 2 } else { chars / 2 + 1 };

    let charIter : Iter<Char> = if charsEven {
      hex.chars();
    } else {
      prepend('0', hex.chars());
    };

    let hexBytes = pairs<Char>(charIter);
    var err : ?Text = null;

    func getChar(_ : Nat) : Nat8 {
      let ?(high, low) = hexBytes.next() else unreachable();

      switch (decodeNibble(high), decodeNibble(low)) {
        case (?a, ?b) return (a * 16) + b;
        case (_, _) {
          if (err == null) {
            err := ?("Invalid hex byte: " # escape(Char.toText(high) # Char.toText(low)));
          };
          return 0;
        };
      };
    };

    var arr = Array.tabulate<Nat8>(size, getChar);

    switch (err) {
      case (?err) return #err(err);
      case (null) return #ok(arr);
    };
  };

  /// Convert hex Text into a byte array.
  /// This just removes all separator, prefixes and postfixes from the string and then attemts to parse it.
  /// If any of the separators or strings overlap with the hex values, the results can be unexpected and not match the original values!
  /// e.g. if the separator in `options.sep` is set to "a", then all "a"s will be removed from the input, independend of the exact position.
  public func toArrayFormat(hex : Text, options : Format) : Result<[Nat8]> {
    if (hex == options.empty) return #ok([]);

    // remove pre and first preItem
    let ?withoutPre = Text.stripStart(hex, #text(options.pre # options.preItem)) else return #err("Hex value does not start with " # escape(options.pre # options.preItem) # ": " # escape(hex));

    // remove post
    let ?withoutPost = Text.stripEnd(withoutPre, #text(options.post)) else return #err("Hex value does not end with " # escape(options.post) # ": " # escape(hex));

    // remove sep and other preItem, if present
    let withoutSep = Text.replace(withoutPost, #text(options.sep # options.preItem), "");

    return toArray(withoutSep);
  };

  /// Convert hex Text into a byte array.
  /// Similar to `toArray` but traps if `hex` contains invalid characters
  public func toArrayUnsafe(hex : Text) : [Nat8] {
    switch (toArray(hex)) {
      case (#ok(data)) return data;
      case (#err(msg)) trap("Hex.toArrayUnsafe: " # msg);
    };
  };

  /// Convert hex Text into a byte array.
  /// Similar to `toArrayFormat` but traps if `hex` contains invalid characters
  public func toArrayFormatUnsafe(hex : Text, options : Format) : [Nat8] {
    switch (toArrayFormat(hex, options)) {
      case (#ok(data)) return data;
      case (#err(msg)) trap("Hex.toArrayFormatUnsafe: " # msg);
    };
  };

  /// Decode a single hex character.
  public func decodeNibble(c : Char) : ?Nat8 {
    switch (c) {
      case ('0') { ?0 };
      case ('1') { ?1 };
      case ('2') { ?2 };
      case ('3') { ?3 };
      case ('4') { ?4 };
      case ('5') { ?5 };
      case ('6') { ?6 };
      case ('7') { ?7 };
      case ('8') { ?8 };
      case ('9') { ?9 };
      case ('a') { ?10 };
      case ('b') { ?11 };
      case ('c') { ?12 };
      case ('d') { ?13 };
      case ('e') { ?14 };
      case ('f') { ?15 };
      case ('A') { ?10 };
      case ('B') { ?11 };
      case ('C') { ?12 };
      case ('D') { ?13 };
      case ('E') { ?14 };
      case ('F') { ?15 };
      case (_) { null };
    };
  };

  /// Encode a byte into hex Text containing exactly two hex characters
  public func encodeByte(byte : Nat8) : Text {
    return encodeNibble(byte / 16) # encodeNibble(byte % 16);
  };

  /// Encode a byte into hex Text containing exactly two hex characters
  public func encodeByteUpper(byte : Nat8) : Text {
    return encodeNibbleUpper(byte / 16) # encodeNibbleUpper(byte % 16);
  };

  /// Encode a nibble into a single hex character
  public func encodeNibble(nibble : Nat8) : Text {
    switch (nibble) {
      case (0) { "0" };
      case (1) { "1" };
      case (2) { "2" };
      case (3) { "3" };
      case (4) { "4" };
      case (5) { "5" };
      case (6) { "6" };
      case (7) { "7" };
      case (8) { "8" };
      case (9) { "9" };
      case (10) { "a" };
      case (11) { "b" };
      case (12) { "c" };
      case (13) { "d" };
      case (14) { "e" };
      case (15) { "f" };
      case (_) {
        trap("invalid value in encodeNibble: " # Nat8.toText(nibble));
      };
    };
  };

  /// Encode a nibble into a single hex character
  public func encodeNibbleUpper(nibble : Nat8) : Text {
    switch (nibble) {
      case (0) { "0" };
      case (1) { "1" };
      case (2) { "2" };
      case (3) { "3" };
      case (4) { "4" };
      case (5) { "5" };
      case (6) { "6" };
      case (7) { "7" };
      case (8) { "8" };
      case (9) { "9" };
      case (10) { "A" };
      case (11) { "B" };
      case (12) { "C" };
      case (13) { "D" };
      case (14) { "E" };
      case (15) { "F" };
      case (_) {
        trap("invalid value in encodeNibble: " # Nat8.toText(nibble));
      };
    };
  };

  /// escape text to be safe to show
  func escape(s : Text) : Text {
    var escaped = "";
    let esc = Char.toText('\"');
    for (c in s.chars()) {
      switch (c) {
        case ('\\') { escaped #= esc # esc };
        case ('\"') { escaped #= esc # "\"" };
        case ('\n') { escaped #= esc # "n" };
        case ('\r') { escaped #= esc # "r" };
        case ('\t') { escaped #= esc # "t" };
        case (_) {
          let codepoint = Char.toNat32(c);
          if (codepoint >= 32 and codepoint <= 126) {
            // Printable ASCII
            escaped #= Char.toText(c);
          } else {
            // Non-printable or extended ASCII
            escaped #= utf16_escape(codepoint);
          };
        };
      };
    };
    return "\"" # escaped # "\"";
  };

  /// escape a utf16 codepoint
  func utf16_escape(codepoint : Nat32) : Text {
    if (codepoint <= 0xFFFF) {
      let (_, _, a, b) = Nat32.explode(codepoint);
      return "\\u" # toText([a, b]);
    };
    let cp = codepoint - 0x10000;
    let high = 0xD800 + (cp / 0x400);
    let low = 0xDC00 + (cp % 0x400);
    let (_, _, a, b) = Nat32.explode(high);
    let (_, _, c, d) = Nat32.explode(low);
    return "\\u" # toText([a, b]) # "\\u" # toText([c, d]);
  }

};
