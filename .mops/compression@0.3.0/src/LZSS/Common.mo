import Buffer "mo:base@0/Buffer";

import Utils "../utils";

module {
  type Buffer<A> = Buffer.Buffer<A>;

  /// An entry in the compression table
  public type LzssEntry = {
    /// represents a single byte that wasn't matched
    #literal : Nat8;

    /// represents a reference to a previous sequence of bytes that was matched
    #pointer : (Nat, Nat);
  };

  public type CompressionLevel = {
    /// No compression.
    #none;

    /// Best speed.
    #fast;

    /// Balanced between speed and size.
    #balance;

    /// Best compression.
    #best;
  };

  public let MATCH_WINDOW_SIZE = 32_768;
  public let MATCH_MAX_SIZE = 258;
};
